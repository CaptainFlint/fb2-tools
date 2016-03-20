#1/usr/bin/perl

use strict;
use warnings;
use utf8;

if (scalar(@ARGV) < 3) {
	print "Usage: $0 <newlines-txt> <source-fb2> { --out <target-fb2> | --marks <target-txt> } \n";
	exit 1;
}

sub readFile($) {
	my ($fname) = @_;
	my $f;
	open($f, '<:encoding(UTF-8)', $fname) or die "Failed to open $fname for reading: $!";
	my @res = <$f>;
	close($f);
	return @res;
}

my $fo;
my @txt = map { my $l = $_; $l =~ s/[\x00-\x20\xa0\x{feff}]//g; $l; } readFile($ARGV[0]);
my @fb2 = readFile($ARGV[1]);
# Strip:
# * all footnote references (they have different numbering),
# * all XML tags;
# * leading and trailing space characters,
# then translate XML entities and cut off the first 50 characters of text.
# After that prepare the text for non-strict comparison by removing:
# * all control characters (may appear in newlines-only text files where footnotes refs were);
# * all space characters (to compare sparse text),
# * BOM marker (U+FEFF).
my @fb2s = map {
	my $l = $_;
	$l =~ s|<a l:href="#_ftn\d+"><sup>\d+</sup></a>||g;
	$l =~ s/<[^<>]*>//g;
	$l =~ s/&lt;/</g;
	$l =~ s/&gt;/>/g;
	$l =~ s/&amp;/&/g;
	$l =~ s/^\s+//;
	$l =~ s/\s+$//;
	$l = substr($l, 0, 50);
	$l =~ s/[\x00-\x20\xa0\x{feff}]//g;
	$l;
} @fb2;
# Array containing only non-empty lines from the source txt
my @txts = ();
# Matching from txts index to txt line number
my @txts2txt = ();

# First, collect all requested entries
my @els = ();   # for each index of the txt line => array of fb2 line indices
my $idx = 0;
for (my $i = 0; $i < scalar(@txt); ++$i) {
	next if ($txt[$i] =~ m/^$/);
	$txts2txt[$idx] = $i + 1;  # Adjust to 1-base
	$txts[$idx] = $txt[$i];

	$els[$idx] = [];
	for (my $j = 0; $j < scalar(@fb2s); ++$j) {
		if ($txts[$idx] eq $fb2s[$j]) {
			push @{$els[$idx]}, $j;
		}
	}
	++$idx;
}

# Process the entries
for (my $i = 0; $i < scalar(@els); ++$i) {
	my $num_els = scalar(@{$els[$i]});
	if ($num_els == 0) {
		print "FAILED to find line in fb2: txt index is $txts2txt[$i]\n";
		next;
	}
	if ($num_els > 1) {
		# Multiple entries.
		# Try to eliminate the wrong ones...
		if (($i > 0) && (scalar(@{$els[$i - 1]}) == 1)) {
			@{$els[$i]} = grep { $_ > $els[$i - 1][0] } @{$els[$i]};
		}
		if (($i < scalar(@els) - 1) && (scalar(@{$els[$i + 1]}) == 1)) {
			@{$els[$i]} = grep { $_ < $els[$i + 1][0] } @{$els[$i]};
		}
		$num_els = scalar(@{$els[$i]});
		if ($num_els > 1) {
			print "DUPLICATE found in fb2 for txt line $txts2txt[$i]\n";
		}
	}
}

# If we need only marks, fill in the separate output array
my @marks = ();

# Finally, insert empty lines
for (my $i = scalar(@els) - 1; $i >= 0; --$i) {
	next if (scalar(@{$els[$i]}) != 1);
	my $idx = $els[$i][0];
	my @temp = ();
	if ($ARGV[2] eq '--marks') {
		unshift @temp, $fb2[$idx];
	}
	# If we are at the start of a cite, poem, title or epigraph, go backwards until we get out
	while (1) {
		--$idx;
		# Continue while the current line contains an open tag from the list,
		# and at the same time does not contain the same closing tag (that is, while we are
		# actually inside the tag).
		last if (($fb2[$idx] !~ m/<(stanza|poem|cite|epigraph|title|subtitle)( [^<>]*|)>/) || ($fb2[$idx] =~ m/<\/$1>/));
		if ($ARGV[2] eq '--marks') {
			unshift @temp, $fb2[$idx];
		}
	}
	if ($fb2[$idx] =~ m/<empty-line\/>/) {
		# Empty line already there, skipping
		next;
	}
	++$idx;
	if ($ARGV[2] eq '--marks') {
		unshift @marks, @temp, "\n";
	}
	else {
		my $sp = (($fb2[$idx] =~ m/^(\s+)/) ? $1 : '');
		splice(@fb2, $idx, 0, "$sp<empty-line/>\n");
	}
}

open($fo, '>:encoding(UTF-8)', $ARGV[3]) or die "Failed to open $ARGV[2] for writing: $!";
print $fo $_ foreach (($ARGV[2] eq '--marks') ? @marks : @fb2);
close($fo);
