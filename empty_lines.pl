#1/usr/bin/perl

use strict;
use warnings;

if (scalar(@ARGV) < 3) {
	print "Usage: $0 <reference-txt> <source-fb2> <target-fb2>\n";
	exit 1;
}

sub readFile($) {
	my ($fname) = @_;
	my $f;
	open($f, '<', $fname) or die "Failed to open $fname for reading: $!";
	my @res = <$f>;
	close($f);
	return @res;
}

my $fo;
my @txt = map { my $l = $_; $l =~ s/[ \x0d\x0a]| //g; $l; } readFile($ARGV[0]);
my @fb2 = readFile($ARGV[1]);
# Strip leading/trailing spaces, XML tags and translate XML entities
my @fb2s = map { my $l = $_; $l =~ s/[ \x0d\x0a]| //g; $l =~ s/<[^<>]*>//g; $l =~ s/&lt;/</g; $l =~ s/&gt;/>/g; $l =~ s/&amp;/&/g; $l; } @fb2;

my $last_el = 0;
my @els = ();
for (my $i = 0; $i < scalar(@txt); ++$i) {
	if (($txt[$i] eq '') && ($txt[$i + 1] ne '')) {
		my $done = 0;
		for (my $j = $last_el; $j < scalar(@fb2s); ++$j) {
			if ($txt[$i + 1] eq $fb2s[$j]) {
				push @els, $j;
				$done = 1;
				$last_el = $j;
				last;
			}
		}
		if (!$done) {
			print "FAILED to find line in fb2: $i\n$txt[$i + 1]\n$fb2[3777]\n$fb2s[3777]\n";
#exit;
		}
	}
}

print "Found empty lines:\n" . join("\n", @els) . "\n";

for my $idx (sort { $b <=> $a } @els) {
	my $sp = (($fb2[$idx] =~ m/^(\s+)/) ? $1 : '');
	splice(@fb2, $idx - 1, 0, "$sp<empty-line/>\n");
}

open($fo, '>', $ARGV[2]) or die "Failed to open $ARGV[2] for writing: $!";
print $fo $_ foreach (@fb2);
close($fo);
