#!/usr/bin/perl
use strict;
use warnings;
use LWP::UserAgent;
use HTML::Entities;
use Time::Piece;
use Encode;
use XML::Feed;

# Ensure Unicode prints correctly
binmode(STDOUT, ':encoding(UTF-8)');

my $url = 'https://www.arnewsline.org/?format=rss';

my $ua = LWP::UserAgent->new(
    timeout => 10,
    agent   => 'Mozilla/5.0',
);

my $resp = $ua->get($url);
die "FETCH FAILED: " . $resp->status_line . "\n"
    unless $resp->is_success;

my $feed = XML::Feed->parse(\$resp->decoded_content)
    or die "RSS PARSE FAILED\n";

# Only the most recent report
my ($entry) = $feed->entries
    or die "NO ENTRIES FOUND\n";

my $html = $entry->content->body || '';

# Remove SCRIPT/AUDIO link paragraphs
$html =~ s{<p[^>]*>\s*<a[^>]*>.*?</a>\s*</p>}{}gis;

# Convert HTML line breaks to real newlines
$html =~ s/<br\s*\/?>/\n/gi;

# Strip remaining HTML tags
$html =~ s/<[^>]+>//g;

# Decode HTML entities (this is correct)
decode_entities($html);

# Extract bullet lines
for my $line (split /\n/, $html) {
    next unless $line =~ /^\s*-\s*(.+)$/;
    my $headline = $1;
    $headline =~ s/\s+$//;
    print "ARNewsLine.org: $headline\n";
}

# Fetch source
my $url = 'https://www.ng3k.com/Misc/adxo.html';

my $ua = LWP::UserAgent->new(
    timeout => 15,
    agent   => 'Mozilla/5.0',
);

my $resp = $ua->get($url);
die "NG3K FETCH FAILED: " . $resp->status_line . "\n"
    unless $resp->is_success;

my $html = $resp->decoded_content;

my $today = localtime;
my $max   = 5;
my $count = 0;

while ($html =~ m{
    <tr\s+class="adxoitem".*?>
    \s*<td\s+class="date">(\d{4})\s+([A-Za-z]{3})(\d{2})</td>
    \s*<td\s+class="date">\d{4}\s+([A-Za-z]{3})(\d{2})</td>
    \s*<td\s+class="cty">(.*?)</td>
    .*?
    <span\s+class="call">(.*?)</span>
    .*?
    <td\s+class="qsl">(.*?)</td>
}gxs) {

    last if $count >= $max;

    my ($year, $smon, $sday, $emon, $eday, $entity, $call_html, $qsl) =
        ($1, $2, $3, $4, $5, $6, $7, $8);

    # Normalize days
    $sday =~ s/^0//;
    $eday =~ s/^0//;

    decode_entities($entity);
    decode_entities($qsl);

    # Strip HTML from callsign
    $call_html =~ s/<[^>]+>//g;
    $call_html =~ s/^\s+|\s+$//g;

    # Date objects
    my $start = Time::Piece->strptime(
        "$year $smon $sday", "%Y %b %d"
    );
    my $end = Time::Piece->strptime(
        "$year $emon $eday", "%Y %b %d"
    );

    # Option B: only currently active
    next if $today < $start || $today > $end;

    my $line =
        "NG3K.com: $entity: "
      . "$smon $sday $emon $eday, $year "
      . "-- $call_html -- QSL via: $qsl\n";

    # Final output encoding for HamClock compatibility
    print Encode::encode('ISO-8859-1', $line);

    $count++;
}

binmode(STDOUT, ':encoding(UTF-8)');

my $issues_url = 'https://hamweekly.com/rss/issues.xml';

my $ua = LWP::UserAgent->new(
    timeout => 10,
    agent   => 'Mozilla/5.0',
);

# Fetch issues RSS
my $resp = $ua->get($issues_url);
die "ISSUES FETCH FAILED: " . $resp->status_line . "\n"
    unless $resp->is_success;

my $rss = XML::RSS->new;
$rss->parse($resp->decoded_content);

# Latest issue
my $item = $rss->{items}[0]
    or die "NO ISSUES FOUND\n";

my $issue_url = $item->{link} || $item->{guid}
    or die "NO ISSUE URL\n";

# Fetch issue HTML
my $issue_resp = $ua->get($issue_url);
die "ISSUE FETCH FAILED: " . $issue_resp->status_line . "\n"
    unless $issue_resp->is_success;

my $html = $issue_resp->decoded_content;

# Extract article titles
while ($html =~ m{
    <span\s+class="archive-headline">
    \s*<a[^>]*>
    (.*?)
    </a>
    \s*</span>
}gxis) {
    my $title = $1;
    $title =~ s/<[^>]+>//g;
    decode_entities($title);
    $title =~ s/\s+$//;

    print "HamWeekly.com: $title\n";
}
