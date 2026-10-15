import unittest

from check_ghdl import (CPU_STARTUP_WARNING_PROFILE, classify_cpu_runtime_warnings)


MARKER = {'status':'INFO', 'label':'startup_status_initialized', 'time_ns':277}
EQ_WARNING = '../../src/ieee2008/numeric_std-body.vhdl:1776:7:@0ms:(assertion warning): NUMERIC_STD."=": metavalue detected, returning FALSE'
INTEGER_WARNING = '../../src/ieee2008/numeric_std-body.vhdl:3036:7:@46ns:(assertion warning): NUMERIC_STD.TO_INTEGER: metavalue detected, returning 0'


class CpuRuntimeDiagnosticTests(unittest.TestCase):
    def test_exact_reviewed_startup_profile_passes(self):
        warnings = []
        for (message, time_ns), count in CPU_STARTUP_WARNING_PROFILE.items():
            stamp = '0ms' if time_ns == 0 else f'{time_ns}ns'
            line = EQ_WARNING.replace('@0ms:', f'@{stamp}:') if message.startswith('NUMERIC_STD."="') else INTEGER_WARNING.replace('@46ns:', f'@{stamp}:')
            warnings.extend([line] * count)
        status, details = classify_cpu_runtime_warnings(warnings, [MARKER])
        self.assertEqual(status, 'PASS')
        self.assertEqual(details['startup_initialized_time_ns'], 277)

    def test_no_warnings_passes(self):
        status, _ = classify_cpu_runtime_warnings([], [MARKER])
        self.assertEqual(status, 'PASS')

    def test_warning_after_startup_blocks(self):
        late = EQ_WARNING.replace('@0ms:', '@277ns:')
        reviewed = [EQ_WARNING] * 15 + [INTEGER_WARNING] * 6
        status, details = classify_cpu_runtime_warnings(reviewed + [late], [MARKER])
        self.assertEqual(status, 'WARNING')
        self.assertEqual(len(details['warnings_at_or_after_initialization']), 1)

    def test_changed_startup_profile_blocks(self):
        moved = EQ_WARNING.replace('@0ms:', '@1ns:')
        warnings = [EQ_WARNING] * 7 + [moved] + [INTEGER_WARNING] * 6
        status, _ = classify_cpu_runtime_warnings(warnings, [MARKER])
        self.assertEqual(status, 'WARNING')

    def test_missing_marker_is_not_a_pass(self):
        status, _ = classify_cpu_runtime_warnings([], [])
        self.assertEqual(status, 'ERROR')


if __name__ == '__main__':
    unittest.main()
