$log = 'D:\esp32\firmware\.pio_err.log'
$lines = Get-Content -LiteralPath $log -ErrorAction SilentlyContinue
"log bytes: " + ((Get-Item -LiteralPath $log -ErrorAction SilentlyContinue).Length)
"total build lines captured: " + $lines.Count
"raw 'error' mentions: " + ((Select-String -LiteralPath $log -Pattern 'error' | Measure-Object).Count)
""
"=== distinct error: lines (SORTED + DEDUPED so we see the few REAL bugs, not the cascade) ==="
$errs = $lines | Where-Object { $_ -match 'error:' } | ForEach-Object { $_.Trim() } | Sort-Object -Unique
if ($errs) { $errs } else { "(none matched - log may hold only the first env)" }
""
"=== which env produced them (start/end of each target section in the log) ==="
$lines | Select-String -Pattern 'Processing (gateway|relay)|Environment +Status|gateway +[A-Z]+|relay +[A-Z]+' | ForEach-Object { $_.Line.Trim() } | Sort-Object -Unique
