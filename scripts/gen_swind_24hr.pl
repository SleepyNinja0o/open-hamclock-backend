#!/usr/bin/env perl
use strict;
use warnings;

use LWP::UserAgent;
use JSON qw(decode_json);
use Time::Local qw(timegm);

# ------------------------------------------------------------
# Configuration (env-overridable)
# ------------------------------------------------------------
my $URL         = "https://services.swpc.noaa.gov/products/solar-wind/plasma-3-day.json";
my $WINDOW_SEC  = 24*3600;

# Padding (seed) behavior for fresh installs:
# - If ON, fills any gap between (now-24h) and the first real sample with repeated values.
# - Use a spacing that will survive HamClock thinning; 300s is a safe default.
my $PAD_ON      = 1;
my $PAD_DT      = 300;  # seconds

# Freshness check: if newest real sample is older than this, fail (so cron/logs reveal it)
my $STALE_SEC   = 15*60;

# Optional atomic output file. If unset, prints to STDOUT.
my $OUTFILE     = "/opt/hamclock-backend/htdocs/ham/HamClock/solar-wind/swind-24hr.txt";

# ------------------------------------------------------------
# Fetch NOAA data
# ------------------------------------------------------------
my $ua = LWP::UserAgent->new(
    timeout => 15,
    agent   => 'OHB-SolarWind/1.0',
);

my $resp = $ua->get($URL);
die "ERROR: fetch failed: " . $resp->status_line . "\n" unless $resp->is_success;

my $rows = decode_json($resp->decoded_content);
die "ERROR: bad JSON\n" unless ref $rows eq 'ARRAY' && @$rows > 1;

# ------------------------------------------------------------
# Header row → column index map
# ------------------------------------------------------------
my %col;
for my $i (0 .. $#{$rows->[0]}) {
    $col{ $rows->[0][$i] } = $i;
}

for my $required (qw(time_tag density speed)) {
    die "ERROR: missing column $required\n" unless exists $col{$required};
}

# ------------------------------------------------------------
# Parse rows
# ------------------------------------------------------------
my @samples;

for my $i (1 .. $#$rows) {
    my $row = $rows->[$i];
    next unless ref $row eq 'ARRAY';

    my $time = $row->[ $col{time_tag} ];
    my $dens = $row->[ $col{density} ];
    my $spd  = $row->[ $col{speed} ];

    next unless defined $time && defined $dens && defined $spd;
    next if $dens eq '' || $spd eq '';

    # Strip milliseconds: "YYYY-MM-DD HH:MM:SS.mmm"
    $time =~ s/\.\d+$//;

    # Parse timestamp (UTC)
    my ($Y,$m,$d,$H,$M,$S) =
        $time =~ /^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})$/
        or next;

    my $epoch = eval { timegm($S, $M, $H, $d, $m-1, $Y) };
    next unless defined $epoch;

    push @samples, [ $epoch, $dens + 0, $spd + 0 ];
}

die "ERROR: no usable samples parsed\n" unless @samples;

# Sort by time
@samples = sort { $a->[0] <=> $b->[0] } @samples;

# ------------------------------------------------------------
# Window by time (last 24 hours ending now)
# ------------------------------------------------------------
my $now   = time();
my $start = $now - $WINDOW_SEC;

# keep only [start .. now], allow slight future skew (+120s) but clamp later
@samples = grep { $_->[0] >= $start && $_->[0] <= $now + 120 } @samples;

die "ERROR: no samples in last window (start=$start now=$now)\n" unless @samples;

# Clamp any slight-future timestamps down to now (rare, but avoids weirdness)
for my $s (@samples) {
    $s->[0] = $now if $s->[0] > $now;
}

# Freshness guard: newest point must be reasonably recent
my $newest = $samples[-1]->[0];
if ($newest < $now - $STALE_SEC) {
    die "ERROR: solar wind feed stale (newest=$newest now=$now age=" . ($now - $newest) . "s)\n";
}

# ------------------------------------------------------------
# Optional padding for fresh installs
# ------------------------------------------------------------
if ($PAD_ON) {
    my $first_t = $samples[0]->[0];
    if ($first_t > $start) {
        my ($dens0, $spd0) = ($samples[0]->[1], $samples[0]->[2]);

        my @pad;
        # Generate points from start up to just before first_t, spaced by PAD_DT
        for (my $t = $start; $t < $first_t; $t += $PAD_DT) {
            push @pad, [ $t, $dens0, $spd0 ];
        }

        # Prepend padding
        @samples = (@pad, @samples);
    }
}

# ------------------------------------------------------------
# Emit HamClock-compatible output: "epoch density speed"
# Optionally write atomically to OUTFILE
# ------------------------------------------------------------
my $out_fh;
my $tmpfile;

if (defined $OUTFILE && length $OUTFILE) {
    $tmpfile = "$OUTFILE.tmp.$$";
    open($out_fh, '>', $tmpfile) or die "ERROR: cannot open tmpfile $tmpfile: $!\n";
} else {
    $out_fh = *STDOUT;
}

for my $s (@samples) {
    printf {$out_fh} "%d %.2f %.1f\n", $s->[0], $s->[1], $s->[2];
}

if (defined $OUTFILE && length $OUTFILE) {
    close($out_fh) or die "ERROR: close failed for $tmpfile: $!\n";
    rename($tmpfile, $OUTFILE) or die "ERROR: rename $tmpfile -> $OUTFILE failed: $!\n";
}
