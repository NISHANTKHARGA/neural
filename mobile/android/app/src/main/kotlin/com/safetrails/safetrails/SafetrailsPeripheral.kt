package com.safetrails.safetrails

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothGattServer
import android.bluetooth.BluetoothGattServerCallback
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.content.Context
import android.os.ParcelUuid
import android.util.Log
import java.nio.charset.StandardCharsets
import java.util.UUID

/**
 * Turns the phone into a SAFETRAILS relay over BLE (peripheral / GATT server
 * role): it advertises the SAFETRAILS service, accepts writes from a peer
 * phone (the SAFETRAILS client), and notifies packets back. Mirrors the same
 * service/characteristic layout as the ESP32 relay so a phone can be reached
 * exactly like hardware (shared/protocol/PROTOCOL.md §3).
 *
 * Dart communication:
 *  - MethodChannel "safetrails/peripheral": start / stop / notify
 *  - EventChannel "safetrails/peripheral/events": wrote / subscribed /
 *    unsubscribed / connecting / advertisingStopped
 */
class SafetrailsPeripheral(private val context: Context) {

    companion object {
        private const val TAG = "SafetrailsPeripheral"

        val SERVICE_UUID = UUID.fromString("2f32f800-6a00-4f6a-9a5e-001122334455")
        val SOS_TX      = UUID.fromString("2f32f801-6a00-4f6a-9a5e-001122334455")
        val SOS_RX      = UUID.fromString("2f32f802-6a00-4f6a-9a5e-001122334455")
        val ACL_TX      = UUID.fromString("2f32f803-6a00-4f6a-9a5e-001122334455")
        val RESCUE_RX   = UUID.fromString("2f32f804-6a00-4f6a-9a5e-001122334455")
        val BROADCAST_RX= UUID.fromString("2f32f805-6a00-4f6a-9a5e-001122334455")
        val STATUS_RX   = UUID.fromString("2f32f806-6a00-4f6a-9a5e-001122334455")
        val DATA_RX     = UUID.fromString("2f32f807-6a00-4f6a-9a5e-001122334455")

        val CCCD = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

        fun charKey(uuid: UUID): String = when (uuid) {
            SOS_RX -> "sosRx"
            RESCUE_RX -> "rescueRx"
            BROADCAST_RX -> "broadcastRx"
            STATUS_RX -> "statusRx"
            DATA_RX -> "dataRx"
            else -> "other"
        }

        fun charOf(key: String?): UUID? = when (key) {
            "sosRx" -> SOS_RX
            "rescueRx" -> RESCUE_RX
            "broadcastRx" -> BROADCAST_RX
            "statusRx" -> STATUS_RX
            "dataRx" -> DATA_RX
            else -> null
        }
    }

    interface Host {
        fun onEvent(name: String, payload: Map<String, Any?>)
    }

    private lateinit var host: Host

    private val bluetoothManager: BluetoothManager by lazy {
        context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
    }

    private val adapter: BluetoothAdapter by lazy {
        bluetoothManager.adapter
    }

    private var gattServer: BluetoothGattServer? = null
    private var advertiser: BluetoothLeAdvertiser? = null
    private val chars = HashMap<UUID, BluetoothGattCharacteristic>()
    private val connected = HashSet<BluetoothDevice>()

    /**
     * ATT MTU negotiated by the peer central. Android exposes no per-device MTU
     * on the server side, so track the largest value a client requested via its
     * own request; 517 matches the ESP32 and the Dart client.
     */
    @Volatile private var deviceMtu: Int = 517
    @Volatile private var started = false

    @SuppressLint("MissingPermission")
    private val gattCallback = object : BluetoothGattServerCallback() {
        override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {
            when (newState) {
                BluetoothProfile.STATE_CONNECTED -> {
                    connected.add(device)
                    Log.d(TAG, "client connected: ${device.address}")
                    host.onEvent("connecting", mapOf("device" to device.address))
                }
                BluetoothProfile.STATE_DISCONNECTED -> {
                    connected.remove(device)
                    Log.d(TAG, "client disconnected: ${device.address}")
                    host.onEvent("clientDisconnected", mapOf("device" to device.address))
                }
            }
        }

        override fun onCharacteristicReadRequest(
            device: BluetoothDevice,
            requestId: Int,
            offset: Int,
            characteristic: BluetoothGattCharacteristic
        ) {
            gattServer?.sendResponse(
                device, requestId, BluetoothGatt.GATT_SUCCESS, offset,
                characteristic.value ?: byteArrayOf()
            )
        }

        override fun onCharacteristicWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            characteristic: BluetoothGattCharacteristic,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray?
        ) {
            if (responseNeeded) {
                gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, null)
            }
            val data = value?.toString(StandardCharsets.UTF_8) ?: ""
            Log.d(TAG, "client wrote ${characteristic.uuid} ($data)")
            host.onEvent(
                "wrote",
                mapOf("char" to characteristic.uuid.toString(), "data" to data)
            )
        }

        override fun onDescriptorWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            descriptor: BluetoothGattDescriptor,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray?
        ) {
            if (responseNeeded) {
                gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, null)
            }
            val enabled = value.let {
                it != null && it.isNotEmpty() && (it[0].toInt() and 0x01) != 0
            }
            val char = descriptor.characteristic?.uuid ?: return
            val key = charKey(char)
            host.onEvent(if (enabled) "subscribed" else "unsubscribed", mapOf(
                "char" to char.toString(),
                "device" to device.address
            ))
            if (enabled && key == "statusRx") {
                // The client is listening: push an announce right away.
                host.onEvent("announce", mapOf("device" to device.address))
            }
        }
    }

    private val advertiseCallback = object : AdvertiseCallback() {
        override fun onStartSuccess(settingsInEffect: AdvertiseSettings) {
            Log.d(TAG, "advertising started")
            host.onEvent("advertisingStarted", emptyMap())
        }

        override fun onStartFailure(errorCode: Int) {
            Log.d(TAG, "advertising failed: $errorCode")
            host.onEvent("advertisingStopped", mapOf("code" to errorCode))
        }
    }

    /** Start the GATT server and begin advertising the SAFETRAILS service. */
    @SuppressLint("MissingPermission")
    fun start(host: Host, serviceName: String): Boolean {
        this.host = host
        if (started) return true
        return try {
            if (!adapter.isEnabled) {
                host.onEvent("advertisingStopped", mapOf("code" to "adapter-off"))
                return false
            }

            // setIncludeDeviceName(true) publishes the ADAPTER's name, not the
            // serviceName argument. Without this the phone advertises as the
            // handset model ("Galaxy S21") and the scanner's SAFETRAILS_RELAY
            // prefix test fails, so two phones cannot discover each other.
            // Renaming needs BLUETOOTH_CONNECT on API 31+ and throws otherwise.
            try {
                if (adapter.name != serviceName) {
                    adapter.name = serviceName
                    Log.d(TAG, "adapter renamed to $serviceName")
                }
            } catch (e: SecurityException) {
                Log.w(TAG, "cannot rename adapter (needs BLUETOOTH_CONNECT); " +
                    "name-based discovery may fail", e)
            } catch (e: Exception) {
                Log.w(TAG, "adapter rename failed", e)
            }

            val server = bluetoothManager.openGattServer(context, gattCallback) ?: return false
        val service = BluetoothGattService(SERVICE_UUID, BluetoothGattService.SERVICE_TYPE_PRIMARY)

        fun addCharacteristic(uuid: UUID, props: Int, perms: Int): BluetoothGattCharacteristic {
            val c = BluetoothGattCharacteristic(uuid, props, perms)
            if ((props and BluetoothGattCharacteristic.PROPERTY_NOTIFY) != 0) {
                c.addDescriptor(
                    BluetoothGattDescriptor(CCCD, BluetoothGattDescriptor.PERMISSION_READ or BluetoothGattDescriptor.PERMISSION_WRITE)
                )
            }
            service.addCharacteristic(c)
            chars[uuid] = c
            return c
        }

        addCharacteristic(SOS_TX, BluetoothGattCharacteristic.PROPERTY_WRITE, BluetoothGattCharacteristic.PERMISSION_WRITE)
        addCharacteristic(SOS_RX, BluetoothGattCharacteristic.PROPERTY_READ or BluetoothGattCharacteristic.PROPERTY_NOTIFY, BluetoothGattCharacteristic.PERMISSION_READ)
        addCharacteristic(ACL_TX, BluetoothGattCharacteristic.PROPERTY_WRITE, BluetoothGattCharacteristic.PERMISSION_WRITE)
        addCharacteristic(RESCUE_RX, BluetoothGattCharacteristic.PROPERTY_READ or BluetoothGattCharacteristic.PROPERTY_NOTIFY, BluetoothGattCharacteristic.PERMISSION_READ)
        addCharacteristic(BROADCAST_RX, BluetoothGattCharacteristic.PROPERTY_READ or BluetoothGattCharacteristic.PROPERTY_NOTIFY, BluetoothGattCharacteristic.PERMISSION_READ)
        addCharacteristic(STATUS_RX, BluetoothGattCharacteristic.PROPERTY_READ or BluetoothGattCharacteristic.PROPERTY_NOTIFY, BluetoothGattCharacteristic.PERMISSION_READ)
        addCharacteristic(DATA_RX, BluetoothGattCharacteristic.PROPERTY_READ or BluetoothGattCharacteristic.PROPERTY_NOTIFY, BluetoothGattCharacteristic.PERMISSION_READ)

        server.addService(service)
        gattServer = server

        // Advertise the relay NAME, matching the ESP32 firmware which
        // deliberately omits the 128-bit service UUID from its 31-byte legacy
        // payload. The app's scanner (ble_relay_connection.dart) accepts a
        // device on either the service UUID or the SAFETRAILS_RELAY name
        // prefix, so the name is what makes one phone discoverable to another.
        // The UUID goes in the scan response only, which has its own budget.
        val advSettings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
            .setConnectable(true)
            .build()
        val advData = AdvertiseData.Builder()
            .setIncludeDeviceName(true)
            .build()
        val advResponse = AdvertiseData.Builder()
            .addServiceUuid(ParcelUuid(SERVICE_UUID))
            .build()
        advertiser = adapter.bluetoothLeAdvertiser
        try {
            advertiser?.startAdvertising(advSettings, advData, advResponse, advertiseCallback)
        } catch (e: Exception) {
            Log.e(TAG, "startAdvertising failed", e)
            host.onEvent("advertisingStopped", mapOf("code" to "exception"))
        }

        started = true
        return true
        } catch (e: SecurityException) {
            Log.e(TAG, "peripheral start denied by permissions", e)
            host.onEvent("advertisingStopped", mapOf("code" to "permission"))
            false
        } catch (e: Exception) {
            Log.e(TAG, "peripheral start failed", e)
            host.onEvent("advertisingStopped", mapOf("code" to "exception"))
            false
        }
    }

    /** Notify every connected client on the given characteristic key. */
    @SuppressLint("MissingPermission")
    fun notify(key: String, data: String): Boolean {
        val uuid = charOf(key) ?: return false
        val char = chars[uuid] ?: return false
        val bytes = data.toByteArray(StandardCharsets.UTF_8)
        var ok = false
        val server = gattServer ?: return false
        // Android truncates a notify to the negotiated ATT MTU (default 23).
        // A partial JSON packet is unparseable at the far end, so refuse it and
        // say so rather than sending half an SOS.
        val mtu = runCatching { deviceMtu }.getOrDefault(517)
        if (bytes.size > mtu - 3) {
            Log.w(TAG, "notify DROPPED ${key} ($data) : ${bytes.size}B > ${mtu - 3}B MTU limit")
            host.onEvent("notifyDropped", mapOf("char" to key, "size" to bytes.size, "limit" to mtu - 3))
            return false
        }
        char.value = bytes
        for (device in connected) {
            ok = server.notifyCharacteristicChanged(device, char, false) || ok
        }
        if (!ok && connected.isNotEmpty()) {
            Log.w(TAG, "notify failed for ${connected.size} client(s), key=$key")
        }
        return ok
    }

    fun startedNow(): Boolean = started

    @SuppressLint("MissingPermission")
    fun stop() {
        started = false
        try { advertiser?.stopAdvertising(advertiseCallback) } catch (_: Exception) {}
        advertiser = null
        try { gattServer?.close() } catch (_: Exception) {}
        gattServer = null
        chars.clear()
        connected.clear()
    }
}