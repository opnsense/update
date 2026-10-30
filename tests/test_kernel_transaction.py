# SPDX-License-Identifier: BSD-2-Clause

"""Exercise the actual option parser/transaction wrapper with isolated commands."""

import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile
import unittest


SOURCE = Path(__file__).parents[1] / 'src/update/opnsense-update.sh.in'


class TransactionTests(unittest.TestCase):
    def setUp(self):
        self.shell = os.environ.get('TEST_SHELL') or shutil.which('sh')
        if not self.shell:
            self.skipTest('A POSIX shell is required')
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.log = self.root / 'calls'
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.helper = self.bin / 'kernel-cleanup'
        self.script = self.root / 'transaction.sh'
        self.executable(self.helper, '#!/bin/sh\nprintf "CALL:%s:%s\\n" "$1" "$2" >> ' + shlex.quote(self.log.as_posix()) + '\n')
        self.executable(self.bin / 'uuidgen', '#!/bin/sh\necho 11111111-1111-1111-1111-111111111111\n')
        self.executable(self.bin / 'sync', '#!/bin/sh\nexit 0\n')
        self.executable(self.bin / 'lockf', '#!/bin/sh\n'
                        'test "$TEST_LOCK_BUSY" != 1 || exit 75\nshift 4\nexec "$@"\n')
        source = SOURCE.read_text()
        start = source.index('parse_options()\n')
        end = source.index('\nif [ -n "${DO_VERBOSE}" ]; then', start)
        wrapper = source[start:end].replace(
            '/usr/local/opnsense/scripts/firmware/kernel_cleanup.py', self.helper.as_posix()
        ).replace('/var/run/opnsense-update.lock', (self.root / 'update.lock').as_posix())
        preamble = '#!/bin/sh\nset -e\nVERSIONDIR=' + shlex.quote(self.root.as_posix()) + '\n'
        body = '''
if [ -z "${DO_VERSION}${DO_CHECK}${DO_SIZE}${DO_TEST}${DO_MIRROR}${DO_ORIGIN}${DO_LOGFILEg}${DO_LOGFILEG}" ]; then
    if [ "$TEST_NEST" = 1 ]; then
        unset TEST_NEST
        /bin/sh "$0" -k
    fi
    if [ -x "$KERNEL_CLEANUP" ] && [ -n "$DO_KERNEL" ]; then
        "$KERNEL_CLEANUP" record
    fi
fi
exit ${TEST_EXIT:-0}
'''
        # A nested real updater inherits the helper path through its own source.
        body = body.replace('"$KERNEL_CLEANUP"', shlex.quote(self.helper.as_posix()))
        self.executable(self.script, preamble + wrapper + '\n' + body)
        self.env = dict(os.environ)
        self.env.pop('OPNSENSE_KERNEL_TRANSACTION', None)
        self.env.pop('OPNSENSE_KERNEL_OWNER', None)
        self.env['PATH'] = str(self.bin) + os.pathsep + str(Path(self.shell).parent) + os.pathsep + os.environ['PATH']

    def executable(self, path, text):
        path.write_text(text, newline='\n')
        path.chmod(0o755)

    def run_script(self, *args, **env):
        completed = subprocess.run([self.shell, self.script.as_posix(), *args],
                                   env=dict(self.env, **env), capture_output=True, text=True)
        calls = self.log.read_text().splitlines() if self.log.exists() else []
        return completed, calls

    def test_success_records_once_and_finishes_after_install(self):
        result, calls = self.run_script('-k')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, ['CALL:begin:', 'CALL:record:', 'CALL:finish:0'])

    def test_failure_reaches_exit_trap(self):
        result, calls = self.run_script('-k', TEST_EXIT='9')
        self.assertEqual(result.returncode, 9, result.stderr)
        self.assertEqual(calls[-1], 'CALL:finish:9')

    def test_nested_invocation_does_not_begin_or_finish_outer_transaction(self):
        result, calls = self.run_script('-k', TEST_NEST='1')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, ['CALL:begin:', 'CALL:record:', 'CALL:record:', 'CALL:finish:0'])

    def test_read_only_modes_do_not_acquire_update_transaction(self):
        for option in ('-v', '-c', '-S', '-T', '-M', '-x', '-X', '-O', '-g', '-G'):
            with self.subTest(option=option):
                result, calls = self.run_script(option)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(calls, [])

    def test_original_option_arguments_survive_reexecution(self):
        result, calls = self.run_script('-k', '-l', '/a directory with spaces')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, ['CALL:begin:', 'CALL:record:', 'CALL:finish:0'])

    def test_busy_update_lock_prevents_all_callbacks(self):
        result, calls = self.run_script('-k', TEST_LOCK_BUSY='1')
        self.assertEqual(result.returncode, 75, result.stderr)
        self.assertEqual(calls, [])
        self.assertFalse((self.root / 'kernel-cleanup.pending').exists())

    def test_old_core_keeps_durable_sentinel_and_updates_normally(self):
        self.helper.unlink()
        result, calls = self.run_script('-k')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, [])
        self.assertTrue((self.root / 'kernel-cleanup.pending').exists())

    def test_stale_inherited_transaction_reacquires_lock(self):
        result, calls = self.run_script(
            '-k', OPNSENSE_KERNEL_TRANSACTION='11111111-1111-1111-1111-111111111111',
            OPNSENSE_KERNEL_OWNER='1', TEST_LOCK_BUSY='1'
        )
        self.assertEqual(result.returncode, 75, result.stderr)
        self.assertEqual(calls, [])


if __name__ == '__main__':
    unittest.main()
