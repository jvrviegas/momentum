#!/bin/zsh
# Flags spacing numbers off the 4 pt grid, and views nudged with offset or position.
# Usage: scripts/grid-lint.sh [folder]      (default: Momentum)
# Allowed numbers: 0, 1, 2, and multiples of 4. Better: a token (Space.lg, theme.radius.md).
# Only SwiftUI files are checked (AX code has its own .position). The token files in Momentum/UI/ are skipped.
# Silence one line with a reason: // grid: ok <why>
set -euo pipefail
dir=${1:-${0:A:h:h}/Momentum}
find "$dir" -name '*.swift' -not -path '*/UI/*' -print0 | xargs -0 grep -l --null '^import SwiftUI' | xargs -0 perl -ne '
  BEGIN { $count = 0 }
  if (!/grid: ok/) {
    my @bad;
    while (/(?:\.padding\((?:\.\w+|\[[^\]]*\])?,?\s*|spacing:\s*|(?:min|max|ideal)?(?:[Ww]idth|[Hh]eight):\s*|cornerRadius:\s*)(-?\d+(?:\.\d+)?)\b/g) {
      my $n = $1;
      push @bad, $n unless $n == 0 || $n == 1 || $n == 2 || ($n == int($n) && $n % 4 == 0);
    }
    push @bad, "offset" if /\.offset\(/;
    push @bad, "position" if /\.position\(/;
    if (@bad) { $count++; my $l = $_; $l =~ s/^\s+//; print "$ARGV:$.: off grid (", join(", ", @bad), "): $l"; }
  }
  close ARGV if eof;
  END { if ($count) { print "FAIL grid-lint: $count lines off the grid\n"; exit 1 } print "PASS grid-lint\n" }'
