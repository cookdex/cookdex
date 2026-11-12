"""Run a Windows test command in a kill-on-close job with a per-process memory guard."""
import argparse
import ctypes as c
from ctypes import wintypes as w
import json
from pathlib import Path
import shutil
import subprocess
import sys
import time

SIZE = c.c_size_t
LIMIT = 4_000_000_000
kernel = c.WinDLL('kernel32', use_last_error=True)
psapi = c.WinDLL('psapi', use_last_error=True)


class Basic(c.Structure):
    _fields_ = [('process_time', c.c_int64), ('job_time', c.c_int64), ('flags', w.DWORD),
                ('min_ws', SIZE), ('max_ws', SIZE), ('processes', w.DWORD),
                ('affinity', SIZE), ('priority', w.DWORD), ('scheduling', w.DWORD)]


class Limits(c.Structure):
    _fields_ = [('basic', Basic), ('io', c.c_uint64 * 6), ('process_limit', SIZE),
                ('job_limit', SIZE), ('peak_process', SIZE), ('peak_job', SIZE)]


class Memory(c.Structure):
    _fields_ = [('cb', w.DWORD), ('faults', w.DWORD), ('peak_ws', SIZE), ('ws', SIZE),
                ('pool', SIZE * 4), ('pagefile', SIZE), ('peak_pagefile', SIZE), ('private', SIZE)]


def api(dll, name, result, *args):
    f = getattr(dll, name)
    f.restype, f.argtypes = result, args
    return f


def check(result):
    if not result:
        raise c.WinError(c.get_last_error())
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--log', required=True, type=Path)
    parser.add_argument('--limit', type=int, default=LIMIT)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if not 0 < args.limit <= LIMIT:
        parser.error('limit must be positive and at most 4 GB')
    cmd = args.command
    if cmd[:1] == ['--']:
        cmd = cmd[1:]
    if not cmd:
        parser.error('test command required')
    args.log.parent.mkdir(parents=True, exist_ok=True)
    cmd[0] = shutil.which(cmd[0]) or cmd[0]
    create = api(kernel,'CreateJobObjectW',w.HANDLE,c.c_void_p,w.LPCWSTR)
    close = api(kernel,'CloseHandle',w.BOOL,w.HANDLE)
    configure = api(kernel,'SetInformationJobObject',w.BOOL,w.HANDLE,c.c_int,c.c_void_p,w.DWORD)
    query = api(kernel,'QueryInformationJobObject',w.BOOL,w.HANDLE,c.c_int,c.c_void_p,w.DWORD,c.c_void_p)
    assign = api(kernel,'AssignProcessToJobObject',w.BOOL,w.HANDLE,w.HANDLE)
    kill = api(kernel,'TerminateJobObject',w.BOOL,w.HANDLE,w.UINT)
    open_process = api(kernel,'OpenProcess',w.HANDLE,w.DWORD,w.BOOL,w.DWORD)
    memory_info = api(psapi,'GetProcessMemoryInfo',w.BOOL,w.HANDLE,c.c_void_p,w.DWORD)
    resume = api(c.WinDLL('ntdll'),'NtResumeProcess',c.c_long,w.HANDLE)
    job = check(create(None,None))
    peaks = {}
    exceeded = None
    result = 1
    child = None
    try:
        limits = Limits()
        # Kernel backstop even between samples. Closing the wrapper ends every child.
        limits.basic.flags = 0x2000 | 0x100
        limits.process_limit = args.limit
        check(configure(job,9,c.byref(limits),c.sizeof(limits)))
        child = subprocess.Popen(cmd,creationflags=0x4)
        check(assign(job,int(child._handle)))
        if resume(int(child._handle)) != 0:
            raise RuntimeError('Failed to resume the guarded test')
        ids = c.create_string_buffer(8 + 1024*c.sizeof(SIZE))
        while child.poll() is None:
            check(query(job,3,ids,c.sizeof(ids),None))
            count = w.DWORD.from_buffer(ids,4).value
            for pid in (SIZE*count).from_buffer(ids,8):
                handle = open_process(0x1000 | 0x10,False,pid)
                if not handle:
                    continue
                try:
                    info = Memory()
                    info.cb = c.sizeof(info)
                    if not memory_info(handle,c.byref(info),info.cb):
                        continue
                    peak = max(info.peak_ws,info.peak_pagefile,info.private)
                    peaks[pid] = max(peak,peaks.get(pid,0))
                    if peak >= args.limit * .98:
                        exceeded = pid
                        check(kill(job,4))
                        break
                finally:
                    close(handle)
            if exceeded:
                break
            time.sleep(.2)
        result = child.wait()
    finally:
        if child is not None and child.poll() is None:
            child.kill()
        close(job)
        report = {
            'limitBytes': args.limit,
            'stopThresholdBytes': int(args.limit * .98),
            'suites': [arg for arg in cmd if arg.endswith('_test.dart')],
            'peakBytes': peaks,
            'stoppedPid': exceeded,
            'exitCode': result,
        }
        args.log.write_text(json.dumps(report, indent=2), encoding='utf8')
        if exceeded is not None:
            print(f'Test job stopped for memory usage in PID {exceeded}. See {args.log}.',
                  file=sys.stderr)
    return result


if __name__ == '__main__':
    sys.exit(main())
