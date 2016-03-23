#1/usr/bin/perl

use strict;
use warnings;
use utf8;
use Encode qw/encode decode/; 

my $errh; # Handle to error output file

sub cleanQuotes($) {
	return ($_[0] =~ m/^([\'\"])(.*)\1$/ ? $2 : $_[0]);
}

my @err_msg = ();
my ($txtf, $fb2f, $outf, $repf, $errf);
for my $arg (@ARGV) {
	my $prefix = lc(substr($arg, 0, 5));
	if ($prefix eq '-txt:') {
		$txtf = cleanQuotes(substr($arg, 5));
	}
	elsif ($prefix eq '-fb2:') {
		$fb2f = cleanQuotes(substr($arg, 5));
	}
	elsif ($prefix eq '-out:') {
		$outf = cleanQuotes(substr($arg, 5));
	}
	elsif ($prefix eq '-rep:') {
		$repf = cleanQuotes(substr($arg, 5));
	}
	elsif ($prefix eq '-err:') {
		$errf = cleanQuotes(substr($arg, 5));
	}
	else {
		push @err_msg, "\tunknown argument: '$arg'";
	}
}

push @err_msg, "\t-txt argument must be present" if (!$txtf);
push @err_msg, "\t-fb2 argument must be present" if (!$fb2f);
push @err_msg, "\tat least one of the arguments -out and -rep must be present" if (!$outf && !$repf);
if (scalar(@err_msg) > 0) {
	print "Input arguments are invalid:\n";
	print join("\n", @err_msg);
	print "\n\nUsage: $0 -txt:<newlines-txt> -fb2:<source-fb2> [-out:<target-fb2>] [-rep:<target-txt>] [-err:<errors-txt>]\n";
	exit 1;
}

sub printError($) {
	my ($str) = @_;
	print $errh $str if ($errh);
	print encode("cp866", $str);    # Windows console works in cp866 by default, translate the text into it (as much as possible)
}

sub readFile($) {
	my ($fname) = @_;
	my $f;
	open($f, '<:encoding(UTF-8)', $fname) or die "Failed to open $fname for reading: $!";
	# Read the file contents and remove the BOM marker (U+FEFF)
	my @res = map { s/\x{feff}//gr } <$f>;
	close($f);
	return @res;
}

my @txt = readFile($txtf);
my @fb2 = readFile($fb2f);

if ($errf) {
	open($errh, '>:encoding(UTF-8)', $errf) or die "Failed to open output file '$errf' for writing: $!";
	print $errh "\x{feff}";
}

# Strip:
# * all footnote references (they are not present in the text file),
# * all XML tags;
# * leading and trailing space characters;
# then translate XML entities and cut off the first 50 characters of text.
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
	# Remove remaining trailing whitespaces
	$l =~ s/\s+$//;
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
	# Remove control characters
	my $ln = ($txt[$i] =~ s/[\x00-\x1f]//gr);
	# Remove trailing whitespaces
	$ln =~ s/\s+$//;
	next if ($ln =~ m/^$/);
	$txts2txt[$idx] = $i + 1;  # Adjust to 1-base
	$txts[$idx] = $ln;

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
		printError("FAILED to find line in fb2: txt index is $txts2txt[$i]: " . $txt[$txts2txt[$i] - 1]);
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
			printError("DUPLICATE found in fb2 for txt line $txts2txt[$i]: " . $txt[$txts2txt[$i] - 1]);
		}
	}
}

# If we need only marks, fill in the separate output array
my @rep = ();

# Finally, insert empty lines
for (my $i = scalar(@els) - 1; $i >= 0; --$i) {
	next if (scalar(@{$els[$i]}) != 1);
	my $idx = $els[$i][0];
	my @temp = ();  # Temporary block of data for inserting into @rep
	unshift @temp, $fb2[$idx];

	# If we are at the start of a cite, poem, title or epigraph, go backwards until we get out
	while (1) {
		--$idx;
		# Continue while the current line contains an open tag from the list,
		# and at the same time does not contain the same closing tag (that is, while we are
		# actually inside the tag).
		last if (($fb2[$idx] !~ m/<(stanza|poem|cite|epigraph|title|subtitle)( [^<>]*|)>/) || ($fb2[$idx] =~ m/<\/$1>/));
		unshift @temp, $fb2[$idx];
	}
	if ($fb2[$idx] =~ m/<empty-line\/>/) {
		# Empty line already there, skipping
		next;
	}
	++$idx;
	unshift @rep, @temp, "\n";
	my $sp = (($fb2[$idx] =~ m/^(\s+)/) ? $1 : '');
	splice(@fb2, $idx, 0, "$sp<empty-line/>\n");
}

my $fo;
if ($outf) {
	open($fo, '>:encoding(UTF-8)', $outf) or die "Failed to open $outf for writing: $!";
	print $fo $_ foreach (@fb2);
	close($fo);
}
if ($repf) {
	open($fo, '>:encoding(UTF-8)', $repf) or die "Failed to open $repf for writing: $!";
	print $fo $_ foreach (@rep);
	close($fo);
}

if ($errf) {
	close($errh);
}
