/**
 * The Windows sound mixer: one PowerShell process for as long as sound is on, playing through WPF's MediaPlayer, one
 * player per sound, mixed by Windows. It loops a bed, crossfades one bed into the next, fades the bed's level, and plays
 * one-shots from players opened ahead, so a one-shot only seeks and plays.
 *
 * `$.process.spawn` closes a child's standard input once its `input` is written, so commands reach the mixer through a
 * file instead: the mixer makes `commands.txt` in a folder of its own under the Windows temp folder, says `ready <path>`
 * on its output, and polls the file every POLL_MS. The mod writes the whole file each time, every command it has not
 * seen answered, each line `<seq> <verb> <words>`, then `end`; the mixer reads it when its time or length changes, and
 * at least every STEADY_MS, so a rewrite of the same length in the same tick is not missed. A poll that finds the file
 * missing or not ended tries again on the next. It runs each line whose seq is above the last it ran, and answers
 * `ok <seq>`, then `sounding <seq>` once a one-shot's position has moved. It says `pid <id>` at start, for
 * /bedroom sound. It writes a dot every BEAT_MS: once its output is closed the write fails and it stops. It also stops,
 * fading everything out over STOP_FADE_MS, when no command has come for QUIET_MS (the mod pings every PING_MS while
 * it runs, so a mod that has gone, or a session left running with no window, is heard for at most that long), and when
 * the process that started it has gone, looked for every PARENT_MS. It stops with exit code 0 after `quit`, the quiet
 * limit or its parent going, and with 4, after an `error` line, when anything else fails; either way it deletes its
 * folder.
 */

/** How often the mixer reads the command file and steps its fades, in ms. */
export const POLL_MS = 10
/**
 * A bed that is not fading is looked at this often, in ms, and every poll once it is within NEAR_END_MS of its end,
 * where it is sought back to its start.
 */
export const STEADY_MS = 100
export const NEAR_END_MS = 150
/** How often the mixer readies its one-shots' players that have played, in ms: a one-shot played again sooner opens another. */
export const ARM_MS = 50
/** How often the mixer writes a dot, in ms. */
export const BEAT_MS = 250
/** The mixer stops when no command has come for this long; the mod pings every PING_MS while it runs, beds or none. */
export const QUIET_MS = 9000
export const PING_MS = 3000
/** How fast the mixer fades everything out when it stops by itself, in ms, and how often it looks for its parent. */
export const STOP_FADE_MS = 500
export const PARENT_MS = 1000

/**
 * One command to the mixer. Gains are 0 to 1, times in ms, names relative to the sounds folder. A bed's `from` is the
 * level its voice starts at in place of silence, for a cross-fade picked up partway. `to` brings the bed voice playing
 * `name` (another of that name fades out; with none, one starts from silence) to `gain` over `fadeMs`, then to `then`
 * over `thenMs`, beside the other beds: two beds held across a long cross-fade. A bed voice brought to 0 ends.
 */
export type MixerCommand =
  | { verb: 'bed'; name: string | undefined; gain: number; fadeMs: number; from?: number }
  | { verb: 'level'; gain: number; fadeMs: number }
  | { verb: 'to'; name: string; gain: number; fadeMs: number; then: number; thenMs: number }
  | { verb: 'shot'; name: string; gain: number }
  | { verb: 'load'; name: string }
  | { verb: 'ping' }
  | { verb: 'quit'; fadeMs: number }

const ms = (value: number): string => String(Math.max(0, Math.round(value)))
const gain = (value: number): string => Math.min(1, Math.max(0, value)).toFixed(4)

/** One command as its line in the file, without its seq. A name holds no space: the bank's names are words and dashes. */
export function wordsOf(command: MixerCommand): string {
  if (command.verb === 'bed') return `bed ${command.name ?? '-'} ${gain(command.gain)} ${ms(command.fadeMs)}${command.from === undefined ? '' : ` ${gain(command.from)}`}`
  if (command.verb === 'level') return `level ${gain(command.gain)} ${ms(command.fadeMs)}`
  if (command.verb === 'to') return `to ${command.name} ${gain(command.gain)} ${ms(command.fadeMs)} ${gain(command.then)} ${ms(command.thenMs)}`
  if (command.verb === 'shot') return `shot ${command.name} ${gain(command.gain)}`
  if (command.verb === 'load') return `load ${command.name}`
  if (command.verb === 'quit') return `quit ${ms(command.fadeMs)}`
  return 'ping'
}

/** The whole command file: the commands not yet answered, oldest first, then `end`. */
export function fileOf(pending: readonly { seq: number; command: MixerCommand }[]): string {
  return [...pending.map(({ seq, command }) => `${seq} ${wordsOf(command)}`), 'end', ''].join('\n')
}

/** One line of the mixer's output, read. */
export type MixerLine = { kind: 'ready'; path: string } | { kind: 'ok' | 'sounding'; seq: number } | { kind: 'pid'; pid: number } | { kind: 'error'; text: string }

/**
 * The lines in a piece of the mixer's output; `rest` is a line not yet ended. Dots are its heartbeat and say nothing:
 * the mixer writes each line whole, so a dot only ever comes before a line, never inside one.
 */
export function linesOf(text: string): { lines: MixerLine[]; rest: string } {
  const parts = text.split(/\r?\n/)
  const rest = (parts.pop() ?? '').replace(/^\.+/, '')
  const lines: MixerLine[] = []
  for (const part of parts) {
    const [word = '', ...more] = part.replace(/^\.+/, '').trim().split(' ')
    if (word === 'ready' && more.length > 0) lines.push({ kind: 'ready', path: more.join(' ') })
    else if ((word === 'ok' || word === 'sounding') && /^\d+$/.test(more[0] ?? '')) lines.push({ kind: word, seq: Number(more[0]) })
    else if (word === 'pid' && /^\d+$/.test(more[0] ?? '')) lines.push({ kind: 'pid', pid: Number(more[0]) })
    else if (word === 'error') lines.push({ kind: 'error', text: more.join(' ') })
  }
  return { lines, rest }
}

const BASE64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

/** A script as `-EncodedCommand` takes it: its UTF-16LE bytes in base64. */
export function encodedOf(script: string): string {
  const bytes: number[] = []
  for (let i = 0; i < script.length; i++) bytes.push(script.charCodeAt(i) & 255, script.charCodeAt(i) >> 8)
  let text = ''
  for (let i = 0; i < bytes.length; i += 3) {
    const [a = 0, b, c] = [bytes[i], bytes[i + 1], bytes[i + 2]]
    const n = (a << 16) | ((b ?? 0) << 8) | (c ?? 0)
    text += BASE64[n >> 18]! + BASE64[(n >> 12) & 63]! + (b === undefined ? '=' : BASE64[(n >> 6) & 63]!) + (c === undefined ? '=' : BASE64[n & 63]!)
  }
  return text
}

/** How the mod starts PowerShell: the script encoded, so no quote in it meets the command line. */
export function powershellArgv(script: string): string[] {
  return ['powershell.exe', '-NoProfile', '-NonInteractive', '-EncodedCommand', encodedOf(script)]
}

/**
 * The mixer's script for `powershellArgv`, reading the sounds under `root` (a Windows path). A voice is one
 * player with a fade: its level moves from `a` to `b` over `n` ms from `t`, on a quarter sine, so two voices crossing
 * keep the same power. A bed loops by seeking to its start just before its end; its files are cut so the end runs
 * into the start.
 */
export function mixerScript(root: string): string {
  return [
    "$ErrorActionPreference='Stop'",
    'Add-Type -AssemblyName PresentationCore',
    `$root='${root.replaceAll("'", "''")}'`,
    "$dir=Join-Path ([IO.Path]::GetTempPath()) ('claude-bedroom-sound-'+$PID)",
    '[void][IO.Directory]::CreateDirectory($dir)',
    "$file=Join-Path $dir 'commands.txt'",
    "[IO.File]::WriteAllText($file,'')",
    '$clock=[Diagnostics.Stopwatch]::StartNew()',
    'function Say($t){[Console]::Out.Write($t+"`n");[Console]::Out.Flush()}',
    "function Open($n){$p=New-Object System.Windows.Media.MediaPlayer;$p.Volume=0;$p.Open([Uri](Join-Path $root $n.Replace('/','\\')));$p}",
    'function Level($v,$now){if($v.n -le 0){return $v.b};$f=[Math]::Min(1,[Math]::Max(0,($now-$v.t)/$v.n));if($v.b -ge $v.a){$v.a+($v.b-$v.a)*[Math]::Sin($f*1.5707963)}else{$v.b+($v.a-$v.b)*[Math]::Cos($f*1.5707963)}}',
    'function Fade($v,$to,$n,$now){$v.a=Level $v $now;$v.b=$to;$v.t=$now;$v.n=$n;$v.n2=0}',
    '$voices=New-Object System.Collections.ArrayList',
    '$shots=@{}',
    '$waits=New-Object System.Collections.ArrayList',
    '$last=0;$seen=0;$beat=-1000;$armedAt=0;$stamp=\'\';$reread=0;$quit=-1;$code=0;$looked=0',
    `function Stop($now){if($script:quit -lt 0){foreach($v in $voices){Fade $v 0 ${STOP_FADE_MS} $now;$v.drop=$true};$script:quit=$now+${STOP_FADE_MS}}}`,
    'function Shot($n){if(-not $shots.ContainsKey($n)){$shots[$n]=New-Object System.Collections.ArrayList};$pool=$shots[$n];foreach($s in $pool){if($s.armed -or $s.until -eq 0){return $s}};$s=[pscustomobject]@{p=(Open $n);until=0;armed=$false;from=0;long=$false};[void]$pool.Add($s);$s}',
    "function Run($w,$now){switch($w[1]){'bed'{foreach($v in $voices){if($v.bed -and -not $v.drop){Fade $v 0 ([int]$w[4]) $now;$v.drop=$true}};if($w[2] -ne '-'){$v=[pscustomobject]@{p=(Open $w[2]);loop=$true;bed=$true;drop=$false;name=$w[2];a=$(if($w.Count -gt 5){[double]$w[5]}else{0});b=[double]$w[3];t=$now;n=[int]$w[4];b2=0;n2=0};[void]$voices.Add($v);$v.p.Play()}}'to'{$hit=$false;foreach($v in $voices){if($v.bed -and $v.name -eq $w[2]){if($hit){Fade $v 0 ([int]$w[4]) $now;$v.drop=$true}else{Fade $v ([double]$w[3]) ([int]$w[4]) $now;$v.drop=$false;$v.b2=[double]$w[5];$v.n2=[int]$w[6];$hit=$true}}};if(-not $hit){$v=[pscustomobject]@{p=(Open $w[2]);loop=$true;bed=$true;drop=$false;name=$w[2];a=0;b=[double]$w[3];t=$now;n=[int]$w[4];b2=[double]$w[5];n2=[int]$w[6]};[void]$voices.Add($v);$v.p.Play()}}'level'{foreach($v in $voices){if($v.bed -and -not $v.drop){Fade $v ([double]$w[2]) ([int]$w[3]) $now}}}'shot'{$s=Shot $w[2];$s.armed=$false;$s.p.Volume=[double]$w[3];if($s.p.Position.TotalMilliseconds -gt 0){$s.p.Position=[TimeSpan]::Zero};$s.p.Play();$s.from=$now;$s.long=$true;$s.until=$now+60000;[void]$waits.Add([pscustomobject]@{p=$s.p;seq=$w[0];by=$now+2000})}'load'{if(-not $shots.ContainsKey($w[2])){$shots[$w[2]]=New-Object System.Collections.ArrayList;[void]$shots[$w[2]].Add([pscustomobject]@{p=(Open $w[2]);until=0;armed=$false;from=0;long=$false})}}'quit'{foreach($v in $voices){Fade $v 0 ([int]$w[2]) $now;$v.drop=$true};$script:quit=$now+[int]$w[2]}};Say ('ok '+$w[0])}",
    "Say ('ready '+$file)",
    "Say ('pid '+$PID)",
    "try{$parent=[int](Get-CimInstance Win32_Process -Filter ('ProcessId='+$PID)).ParentProcessId}catch{$parent=0}",
    '$i=New-Object IO.FileInfo $file;$nextVoices=0',
    'try{while($true){' +
      '$now=$clock.ElapsedMilliseconds;' +
      `$i.Refresh();if($i.Exists){$key=''+$i.LastWriteTimeUtc.Ticks+' '+$i.Length;if($key -ne $stamp -or $now -ge $reread){$reread=$now+${STEADY_MS};try{` +
      "$fs=[IO.File]::Open($file,'Open','Read','ReadWrite,Delete');$r=New-Object IO.StreamReader $fs;$text=$r.ReadToEnd();$r.Close()}catch{$text=''};if($text.EndsWith(\"end`n\")){$stamp=$key;$todo=@();foreach($line in $text.Split(\"`n\")){$w=$line.Trim().Split(' ');$n=0;if($w.Count -lt 2 -or -not [int]::TryParse($w[0],[ref]$n) -or $n -le $last){continue};$todo+=,$w};foreach($w in $todo){if($w[1] -eq 'shot'){Run $w $now}};foreach($w in $todo){if($w[1] -ne 'shot'){Run $w $now};$last=[Math]::Max($last,[int]$w[0]);$seen=$now;$nextVoices=$now}}}};" +
      `if($now -ge $nextVoices){$soon=$false;for($k=$voices.Count-1;$k -ge 0;$k--){$v=$voices[$k];if($v.n2 -gt 0 -and $now -ge $v.t+$v.n){$b2=$v.b2;$n2=$v.n2;Fade $v $b2 $n2 ($v.t+$v.n)};$v.p.Volume=(Level $v $now);if($now -lt $v.t+$v.n){$soon=$true};if($v.loop -and $v.p.NaturalDuration.HasTimeSpan){$d=$v.p.NaturalDuration.TimeSpan.TotalMilliseconds;$at=$v.p.Position.TotalMilliseconds;if($at -ge $d-25){$v.p.Position=[TimeSpan]::Zero;$v.p.Play()}elseif($d-$at -lt ${NEAR_END_MS}){$soon=$true}}else{$soon=$true};if(($v.drop -or ($v.bed -and $v.b -le 0 -and $v.n2 -le 0)) -and $now -ge $v.t+$v.n){$v.p.Close();$voices.RemoveAt($k)}};$nextVoices=$now+$(if($soon){0}else{${STEADY_MS}})};` +
      `if($now-$armedAt -ge ${ARM_MS}){$armedAt=$now;foreach($pool in $shots.Values){foreach($s in $pool){if(-not $s.armed -and $s.until -gt 0){if($s.long -and $s.p.NaturalDuration.HasTimeSpan){$s.until=$s.from+$s.p.NaturalDuration.TimeSpan.TotalMilliseconds+50;$s.long=$false};if($now -ge $s.until){$s.p.Stop();$s.armed=$true}}}}};` +
      "for($k=$waits.Count-1;$k -ge 0;$k--){$x=$waits[$k];if($x.p.Position.TotalMilliseconds -gt 0){Say ('sounding '+$x.seq);$waits.RemoveAt($k)}elseif($now -gt $x.by){$waits.RemoveAt($k)}};" +
      `if($quit -ge 0 -and $now -ge $quit){break};if($now-$seen -gt ${QUIET_MS}){Stop $now};` +
      `if($parent -gt 0 -and $now-$looked -ge ${PARENT_MS}){$looked=$now;try{[void][Diagnostics.Process]::GetProcessById($parent)}catch{Stop $now}};` +
      `if($now-$beat -ge ${BEAT_MS}){$beat=$now;[Console]::Out.Write('.');[Console]::Out.Flush()};` +
      `Start-Sleep -Milliseconds ${POLL_MS}` +
      "}}catch{$code=4;$e=''+$_;try{Say ('error '+$e)}catch{}}finally{foreach($v in $voices){$v.p.Close()};foreach($pool in $shots.Values){foreach($s in $pool){$s.p.Close()}};Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue}",
    'exit $code',
  ].join(';')
}
