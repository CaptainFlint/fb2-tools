#!/usr/bin/perl

# Tests performed:
# 1. Check that all links lead to existing targets.
# 2. Check that each target has at least one link leading to it
#    (if not it's not an error, but very suspicios situation).

# TODO:
# * If there is a link, its target should contain a back-link.

use strict;
use warnings;

if ((scalar(@ARGV) < 1) || ($ARGV[0] eq '-h') || ($ARGV[0] eq '--help')) {
	print "Usage: $0 <fb2-file> [<output-file>]\n";
	exit 1;
}

sub inArray($$) {
	my ($elem, $arr) = @_;
	for my $e (@$arr) {
		return 1 if ($e eq $elem);
	}
	return 0;
}

my $fi;
my $fo;

open($fi, '<', $ARGV[0]) or die "Failed to open input file '$ARGV[0]' for reading: $!";
if ($ARGV[1]) {
	open($fo, '>', $ARGV[1]) or die "Failed to open output file '$ARGV[1]' for writing: $!";
}
else {
	$fo = \*STDOUT;
}

my %links = ();
my %targets = ();

while (my $ln = <$fi>) {
	$ln =~ s/<[^<>]+ id="([^\"]+)"/$targets{$1} = 1; $&;/eg;
	$ln =~ s/<a l:href="#([^\"]+)"/$links{$1} = 1; $&;/eg;
}

print $fo "Invalid links:\n";
for my $i (sort(keys(%links))) {
	print $fo "$i\n" if (!$targets{$i});
}

print $fo "\n";

print $fo "Orfan targets:\n";
for my $i (sort(keys(%targets))) {
	print $fo "$i\n" if (!$links{$i});
}

close($fi);
close($fo) if ($fo != \*STDOUT);
