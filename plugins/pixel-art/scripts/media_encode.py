# GENERATED from lib/media-render/media_encode.py by scripts/sync-shared-copies.sh. Do not edit this copy:
# edit the canonical source, then rerun the script.
"""ffmpeg by subprocess, through named encode profiles (ADR 0103). Standard library only.

PROFILES   one named argument set per caller: a moved plugin keeps its own arguments under its own name.
run(args, cwd=None, report=False, text=True, timeout=None)
                                                 ffmpeg -v error -y ARGS (report: -hide_banner -nostats, for
                                                 filters that print to stderr); EncodeError carries stderr;
                                                 a timeout raises subprocess.TimeoutExpired.
probe(args)                                      ffprobe -v error ARGS -> stdout; EncodeError as run.
mux(video, audio, captions, out, profile)        a finished video stream with narration and a soft caption track.
assemble_audio(wav, segments, out)               narration slices and silences, in order, as one WAV.
stills(frames, out, profile, audio, srt, ass, cwd) held frames -> one video, keyframe per frame, captions burned
                                                 from ass and kept soft from srt; encoded once.
stitcher(command, inputs, out)                   a custom stitcher: the command template with {inputs} and {out}.
"""
import shlex
import subprocess
from pathlib import Path

_SOFT = ['-c:s', 'mov_text', '-metadata:s:s:0', 'language=eng']
PROFILES = {
    # explainer-video's manim renders: video copied as manim encoded it, narration as AAC.
    'explainer-manim': {'video': ['-c:v', 'copy'], 'audio': ['-c:a', 'aac'], 'subtitle': _SOFT},
    # reviewer media: visible quality first (4K frames, CRF 18, keyframe per held frame), encoded once.
    'reviewer-stills': {'fps': 30,
                        'video': ['-c:v', 'libx264', '-preset', 'slow', '-crf', '18', '-tune', 'stillimage',
                                  '-pix_fmt', 'yuv420p', '-movflags', '+faststart'],
                        'audio': ['-c:a', 'aac', '-b:a', '128k', '-ac', '1'], 'subtitle': _SOFT},
    # pixel-art's scene capture: the browser's WebM copied as recorded, the scene's looped WAV as Opus.
    'pixel-art-webm': {'video': ['-c:v', 'copy'], 'audio': ['-c:a', 'libopus']},
}


class EncodeError(RuntimeError):
    pass


def _check(r, tool):
    if r.returncode:
        err = r.stderr if isinstance(r.stderr, str) else r.stderr.decode('utf-8', 'replace')
        raise EncodeError(f'{tool} exited {r.returncode}: {err.strip()[-2000:]}')
    return r


def run(args, cwd=None, report=False, text=True, timeout=None):
    level = ['-hide_banner', '-nostats'] if report else ['-v', 'error']
    return _check(subprocess.run(['ffmpeg', *level, '-y', *map(str, args)], cwd=cwd, capture_output=True,
                                 text=text, timeout=timeout), 'ffmpeg')


def probe(args):
    return _check(subprocess.run(['ffprobe', '-v', 'error', *map(str, args)], capture_output=True, text=True),
                  'ffprobe').stdout


def mux(video, audio, captions, out, profile='explainer-manim'):
    p = PROFILES[profile]
    return run(['-i', video, '-i', audio, '-i', captions, '-map', '0:v:0', '-map', '1:a:0', '-map', '2:s:0',
                *p['video'], *p['audio'], *p['subtitle'], out])


def assemble_audio(wav, segments, out):
    """segments: ('narration', from_s, to_s) slices of wav and ('silence', seconds), in order (media_timeline)."""
    parts, chains = [], []
    for i, seg in enumerate(segments):
        if seg[0] == 'narration':
            chains.append(f'[0:a]atrim={seg[1]}:{seg[2]},asetpts=PTS-STARTPTS,aresample=48000,'
                          f'aformat=channel_layouts=mono[s{i}]')
        else:
            chains.append(f'aevalsrc=0:s=48000:c=mono:d={seg[1]}[s{i}]')
        parts.append(f'[s{i}]')
    graph = ';'.join(chains) + f';{"".join(parts)}concat=n={len(parts)}:v=0:a=1[a]'
    return run(['-i', wav, '-filter_complex', graph, '-map', '[a]', '-c:a', 'pcm_s16le', out])


def concat_file(path):
    """One ffconcat `file` line, its quote escaped the way the concat demuxer reads it."""
    return "file '" + str(path).replace("'", "'\\''") + "'"


def concat_list(frames):
    """ffconcat text for [(png, seconds)]; the last frame is listed twice so its duration holds."""
    lines = ['ffconcat version 1.0']
    for png, seconds in frames:
        lines += [concat_file(Path(png).name), f'duration {seconds:.3f}']
    lines.append(concat_file(Path(frames[-1][0]).name))
    return '\n'.join(lines) + '\n'


def stills(frames, out, profile='reviewer-stills', audio=None, srt=None, ass=None, cwd=None):
    """frames: [(png, seconds)], all in cwd (relative names keep the filter arguments free of escaping)."""
    p = PROFILES[profile]
    cwd = Path(cwd or Path(frames[0][0]).parent)
    (cwd / 'frames.ffconcat').write_text(concat_list(frames), encoding='utf-8')
    total, t, keys = sum(s for _, s in frames), 0.0, []
    for _, s in frames:
        keys.append(f'{t:.3f}')
        t += s
    vf = f'fps={p["fps"]}' + (f',ass={Path(ass).name}' if ass else '') + ',format=yuv420p'
    args = ['-f', 'concat', '-safe', '0', '-i', 'frames.ffconcat']
    maps = ['-map', '0:v:0']
    if audio:
        args += ['-i', audio]
        maps += ['-map', f'{len(maps) // 2}:a:0']
    if srt:
        args += ['-i', srt]
        maps += ['-map', f'{len(maps) // 2}:s:0']
    args += [*maps, '-vf', vf, '-force_key_frames', ','.join(keys), *p['video']]
    args += (p['audio'] if audio else []) + (p['subtitle'] if srt else []) + ['-t', f'{total:.3f}', out]
    return run(args, cwd=cwd)


def stitcher(command, inputs, out):
    """A consumer's stitcher command (config `stitcher: {command}`), split with shlex: {inputs} becomes one
    argument per input path and {out} the output path, each substituted after the split, so no path is re-parsed;
    the command runs without a shell, in out's folder, so a relative path never reaches the checkout's files."""
    argv = [part.replace('{out}', str(out)) for part in shlex.split(command)]
    if '{inputs}' in argv:
        k = argv.index('{inputs}')
        argv[k:k + 1] = [str(i) for i in inputs]
    r = subprocess.run(argv, cwd=Path(out).parent, capture_output=True, text=True)
    if r.returncode:
        raise EncodeError(f'stitcher {argv[0]} exited {r.returncode}: {r.stderr.strip()[-2000:]}')
    return r
