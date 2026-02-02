#!/usr/bin/env perl
use strict;
use warnings;
use LWP::UserAgent;

my $URL = 'https://www.sidc.be/silso/DATA/SN_m_tot_V2.0.csv';
my $OUT = '/opt/hamclock-backend/htdocs/ham/HamClock/ssn/ssn-history.txt';

my $ua = LWP::UserAgent->new(
    timeout => 20,
    agent   => 'hamclock-ssn-history/1.1'
);

my $res = $ua->get($URL);
die "ERROR: failed to fetch SILSO monthly data\n"
    unless $res->is_success;

my @rows;

for my $line (split /\n/, $res->decoded_content) {
    next if $line =~ /^\s*#/;

    # year;month;decimal_year;ssn;std;obs;prov
    my @f = split /;/, $line;
    next unless @f >= 4;

    my ($year, $month, $ssn) = @f[0,1,3];

    # HamClock cutoff
    next if $year < 1900;

    next unless defined $ssn && $ssn >= 0;

    # Keep Jan, Mar, May, Jul, Sep, Nov only
    next unless $month =~ /^(1|3|5|7|9|11)$/;

    # Decimal year: year + (month - 1) / 6
    my $decimal = sprintf("%.2f", $year + ($month - 1) / 6);

    push @rows, sprintf("%s %.1f", $decimal, $ssn);
}

die "ERROR: no data parsed from SILSO\n"
    unless @rows;

# Atomic write
my $tmp = "$OUT.tmp";
open my $fh, '>', $tmp or die "ERROR: cannot write temp file\n";
print $fh "$_\n" for @rows;
close $fh;
rename $tmp, $OUT or die "ERROR: rename failed\n";

exit 0;

