$ErrorActionPreference = 'Stop'
$port = 8765
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://127.0.0.1:$port/")
try { $listener.Start() } catch {
  Write-Host 'Cannot start NEO-X on port 8765. Another app may be using the port.' -ForegroundColor Red
  Write-Host $_.Exception.Message
  Read-Host 'Press Enter to close'
  exit 1
}
Write-Host "NEO-X running at http://127.0.0.1:$port/" -ForegroundColor Cyan
Write-Host 'Keep this window open while using NEO-X. Ctrl+C to stop.'
Start-Process "http://127.0.0.1:$port/"
$types = @{'.html'='text/html; charset=utf-8';'.htm'='text/html; charset=utf-8';'.js'='text/javascript; charset=utf-8';'.css'='text/css; charset=utf-8';'.png'='image/png';'.jpg'='image/jpeg';'.jpeg'='image/jpeg';'.svg'='image/svg+xml';'.json'='application/json; charset=utf-8';'.pdf'='application/pdf';'.ico'='image/x-icon';'.webp'='image/webp';'.txt'='text/plain; charset=utf-8'}
try {
 while ($listener.IsListening) {
  $ctx = $listener.GetContext()
  try {
   $response = $ctx.Response
   $response.Headers.Add('X-Content-Type-Options','nosniff')
   $response.Headers.Add('Cache-Control','no-cache')
   if ($ctx.Request.Url.AbsolutePath -eq '/api/neo-ai') {
     $response.ContentType='application/json; charset=utf-8'
     if ($ctx.Request.HttpMethod -ne 'POST') { $response.StatusCode=405; continue }
     try {
       if ($ctx.Request.ContentLength64 -gt 65536) { throw 'Message too large.' }
       $reader=[IO.StreamReader]::new($ctx.Request.InputStream,[Text.Encoding]::UTF8)
       $body=$reader.ReadToEnd(); $reader.Dispose()
       $data=ConvertFrom-Json -InputObject $body
       $messages=@($data.messages | Where-Object { $_.role -in @('user','assistant') -and $_.content -is [string] } | Select-Object -Last 20 | ForEach-Object { @{role=[string]$_.role;content=([string]$_.content).Substring(0,[Math]::Min(6000,([string]$_.content).Length))} })
       if ($messages.Count -lt 1) { throw 'No message provided.' }
       $system=@{role='system';content='You are NEO AI, a helpful educational assistant for Sri Lankan students. Answer in Sinhala if asked in Sinhala, otherwise in the user language. Explain clearly and admit uncertainty.'}
       $all=@($system)+$messages
       $mode=[string]$data.mode
       $model=[string]$data.model
       if ($model -notmatch '^[a-zA-Z0-9_.:/-]{1,100}$') { $model='llama3.2:3b' }
       $provider='offline'; $reply=$null; $offlineError=''
       if ($mode -ne 'online') {
         try {
           $payload=@{model=$model;messages=$all;stream=$false} | ConvertTo-Json -Depth 12 -Compress
           $res=Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/chat' -Method Post -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($payload)) -TimeoutSec 180
           $reply=[string]$res.message.content
           if (-not $reply) { throw 'Empty offline model response.' }
         } catch { $offlineError=$_.Exception.Message; if ($mode -eq 'offline') { throw ('Ollama unavailable or model not downloaded. Run: ollama pull '+$model+'. Details: '+$offlineError) } }
       }
       if (-not $reply) {
         $key=[Environment]::GetEnvironmentVariable('OPENAI_API_KEY')
         if ([string]::IsNullOrWhiteSpace($key)) { throw ('Online API key not configured. Set OPENAI_API_KEY in Windows environment variables and restart NEO-X. '+$(if($offlineError){'Offline: '+$offlineError}else{''})) }
         $provider='online'
         $openMessages=@($all | ForEach-Object { @{role=$_.role;content=$_.content} })
         $payload=@{model='gpt-4.1-mini';input=$openMessages;max_output_tokens=1200} | ConvertTo-Json -Depth 12 -Compress
         $headers=@{Authorization=('Bearer '+$key)}
         $res=Invoke-RestMethod -Uri 'https://api.openai.com/v1/responses' -Method Post -Headers $headers -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($payload)) -TimeoutSec 90
         $reply=(@($res.output | ForEach-Object { $_.content } | Where-Object { $_.type -eq 'output_text' } | ForEach-Object { $_.text }) -join "`n")
         if (-not $reply) { throw 'OpenAI returned no text.' }
       }
       $json=@{reply=$reply;provider=$provider} | ConvertTo-Json -Depth 4 -Compress
     } catch {
       $response.StatusCode=503
       $json=@{error=$_.Exception.Message} | ConvertTo-Json -Compress
     }
     $bytes=[Text.Encoding]::UTF8.GetBytes($json)
     $response.ContentLength64=$bytes.Length
     $response.OutputStream.Write($bytes,0,$bytes.Length)
     continue
   }
   if ($ctx.Request.HttpMethod -notin @('GET','HEAD')) { $response.StatusCode=405; continue }
   $path = [Uri]::UnescapeDataString($ctx.Request.Url.AbsolutePath).TrimStart('/')
   if ([string]::IsNullOrWhiteSpace($path)) { $path='index.html' }
   $path = $path.Replace('/',[IO.Path]::DirectorySeparatorChar)
   $full = [IO.Path]::GetFullPath((Join-Path $root $path))
   $rootFull = [IO.Path]::GetFullPath($root).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
   if (-not $full.StartsWith($rootFull,[StringComparison]::OrdinalIgnoreCase) -or -not [IO.File]::Exists($full) -or [IO.Path]::GetFileName($full) -match '^(START-NEO-X|NEO-X-Server)') { $response.StatusCode=404; continue }
   $ext=[IO.Path]::GetExtension($full).ToLowerInvariant()
   if (-not $types.ContainsKey($ext)) { $response.StatusCode=403; continue }
   $response.ContentType=$types[$ext]
   $bytes=[IO.File]::ReadAllBytes($full)
   $response.ContentLength64=$bytes.Length
   if ($ctx.Request.HttpMethod -eq 'GET') { $response.OutputStream.Write($bytes,0,$bytes.Length) }
  } catch { Write-Host "Request error: $($_.Exception.Message)" } finally { try { $ctx.Response.Close() } catch {} }
 }
} finally { $listener.Stop(); $listener.Close() }
