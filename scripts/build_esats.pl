#!/usr/bin/env perl
use strict;
use warnings;
use LWP::UserAgent;

my $OUT = "/opt/hamclock-backend/htdocs/ham/HamClock/esats/esats.txt";
my $ESATS1 = "/opt/hamclock-backend/scripts/esats_original.txt";

# ------------------------------------------------------------
# 1. Read authoritative NORAD -> name map from esats1.txt
# ------------------------------------------------------------
my %norad_to_name;

open my $fh, "<", $ESATS1 or die "Cannot open $ESATS1: $!";
while (1) {
    my $name = <$fh>;
    my $l1   = <$fh>;
    my $l2   = <$fh>;
    last unless defined $l2;

    chomp($name, $l1, $l2);

    # Extract NORAD ID from TLE line 1 (field 2, strip trailing U)
    my ($norad) = $l1 =~ /^1\s+(\d+)U/;
    die "Failed to parse NORAD ID from: $l1" unless $norad;

    $norad_to_name{$norad} = $name;
}
close $fh;

# ------------------------------------------------------------
# 2. Fetch Celestrak TLE feeds
# ------------------------------------------------------------
my @urls = (
    "https://celestrak.org/NORAD/elements/gp.php?GROUP=amateur&FORMAT=tle",
    "https://celestrak.org/NORAD/elements/gp.php?GROUP=stations&FORMAT=tle",
    "https://celestrak.org/NORAD/elements/gp.php?GROUP=weather&FORMAT=tle",
    "https://celestrak.org/NORAD/elements/gp.php?GROUP=geo&FORMAT=tle",
);

my $ua = LWP::UserAgent->new( timeout => 20 );
my @tle_lines;

for my $url (@urls) {
    my $res = $ua->get($url);
    die "Fetch failed: $url\n" . $res->status_line unless $res->is_success;

    my $content = $res->decoded_content;
    die "HTML detected from $url" if $content =~ /<html/i;

    push @tle_lines, split /\n/, $content;
}

# ------------------------------------------------------------
# 3. Filter and rename by NORAD ID
# ------------------------------------------------------------
open my $out, ">", $OUT or die "Cannot write $OUT: $!";

for (my $i = 0; $i + 2 < @tle_lines; $i += 3) {
    my $rawname = $tle_lines[$i];
    my $l1      = $tle_lines[$i+1];
    my $l2      = $tle_lines[$i+2];

    my ($norad) = $l1 =~ /^1\s+(\d+)U/;
    next unless defined $norad;

    next unless exists $norad_to_name{$norad};

    print $out $norad_to_name{$norad}, "\n";
    print $out $l1, "\n";
    print $out $l2, "\n";
}

# ------------------------------------------------------------
# 4. Append Moon sentinel EXACTLY
# ------------------------------------------------------------
print $out <<'MOON';
Moon
1     1U     1A   26032.68547454  .00000000  00000-0  0000000 0  0011
2     1 331.4749 175.8066 0362000 332.1449 342.5152  0.03660000    12
MOON

close $out;

print "Generated $OUT successfully\n";

