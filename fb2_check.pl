#!/usr/bin/perl

use strict;
use warnings;
use utf8;

if ((scalar(@ARGV) < 1) || ($ARGV[0] eq '-h') || ($ARGV[0] eq '--help')) {
	print "Usage: $0 <fb2-file> [<output-file>]\n";
	exit 1;
}

# TODO:
# * If there is a link, its target should contain a back-link.

# Checks for quotation marks balance
# Input arguments:
#	$ln   - text line to be checked
#	$data - arrayref where messages about disbalance should be added
#	$id   - text line identifier for future references
# Return value:
#	none
sub checkQuotes($$$) {
	my ($ln, $data, $id) = @_;

	# «French» quotes
	my $qo = ($ln =~ s/«/$&/g) || 0;
	my $qc = ($ln =~ s/»/$&/g) || 0;
	if ($qo != $qc) {
		push @$data, "French quotes $qo/$qc at $id";
	}
	# “English” quotes
	$qo = ($ln =~ s/“/$&/g) || 0;
	$qc = ($ln =~ s/”/$&/g) || 0;
	if ($qo != $qc) {
		push @$data, "English quotes $qo/$qc at $id";
	}
}

# List of test procedures
# Each test contains:
# 'enabled' - whether test should be run or not
# 'name'    - user-friendly name of the test
# 'analyze' - function that will be called for each line of the FB2 file;
#             input: 1) the test object itself, 2) the source line to be analyzed, 3) line number
# 'report'  - function that will be called after analyzing alal data
#             input: 1) the test object itself, 2) output handle
# Other fields may be specified and used internally (e.g. 'data' for gathering problems).
my @tests = (
	{
		# File encoding must be UTF-8.
		'enabled' => 1,
		'name' => 'Encoding',
		'data' => [],
		'analyze' => sub ($$$) {
			my ($this, $ln, $idx) = @_;
			if ($ln =~ m/<\?xml .*encoding="([^\"]+)"/) {
				if (lc($1) ne 'utf-8') {
					push @{$this->{'data'}}, "Wrong encoding: '$1'. Expected 'utf-8'.";
				}
			}
		},
		'report' => sub ($$) {
			my ($this, $fo) = @_;
			print $fo join('', map { "\t$_\n" } @{$this->{'data'}});
		}
	},
	{
		# a) All links lead to existing targets.
		# b) Each target has at least one link leading to it (may contain false positives:
		#    orfan ID is not an error, but very suspicios situation).
		'enabled' => 1,
		'name' => 'Broken links / Orfan targets',
		'data' => { 'targets' => {}, 'links' => {} },
		'analyze' => sub ($$$) {
			my ($this, $ln, $idx) = @_;
			$ln =~ s/<[^<>]+ id="([^\"]+)"/$this->{'data'}->{'targets'}->{$1} = 1; $&;/eg;
			$ln =~ s/<a l:href="#([^\"]+)"/$this->{'data'}->{'links'}->{$1} = 1; $&;/eg;
		},
		'report' => sub ($$) {
			my ($this, $fo) = @_;
			print $fo "Broken links:\n";
			for my $elem (sort(keys(%{$this->{'data'}->{'links'}}))) {
				print $fo "\t$elem\n" if (!$this->{'data'}->{'targets'}->{$elem});
			}
			print $fo "Orfan targets:\n";
			for my $elem (sort(keys(%{$this->{'data'}->{'targets'}}))) {
				print $fo "\t$elem\n" if (!$this->{'data'}->{'links'}->{$elem});
			}
		}
	},
	{
		# Mismatched quotes in lines (may contain false positives when long quotation extends
		# over several paragraphs).
		'enabled' => 1,
		'name' => 'Quotes mismatch in lines',
		'data' => [],
		'analyze' => sub ($$$) {
			my ($this, $ln, $idx) = @_;
			checkQuotes($ln, $this->{'data'}, "line $idx");
		},
		'report' => sub ($$) {
			my ($this, $fo) = @_;
			print $fo join('', map { "\t$_\n" } @{$this->{'data'}});
		}
	},
	{
		# Mismatched quotes inside tags.
		'enabled' => 1,
		'name' => 'Quotes mismatch in tags',
		'data' => [],
		'analyze' => sub ($$$) {
			my ($this, $ln, $idx) = @_;
			while ($ln =~ m/<([^<> ]+)( [^<>]*)?>([^<>]+)<\/\1>/g) {
				my ($tag, $params, $contents) = ($1, ($2 || ''), $3);
				my $contents_cut;
				if (length($contents) > 100) {
					$contents_cut = substr($contents, 0, 50) . '<...>' . substr($contents, -50);
				}
				else {
					$contents_cut = $contents;
				}
				checkQuotes($contents, $this->{'data'}, "line $idx: <$tag$params>$contents_cut</$tag>");
			}
		},
		'report' => sub ($$) {
			my ($this, $fo) = @_;
			print $fo join('', map { "\t$_\n" } @{$this->{'data'}});
		}
	},
	{
		# There should be no space after closing italic/bold tag if it is at the end of phrase.
		'enabled' => 1,
		'name' => 'Spaces after italic/bold',
		'data' => [],
		'analyze' => sub ($$$) {
			my ($this, $ln, $idx) = @_;
			my $num = ($ln =~ s/<\/(emphasis|strong)>\s([.,?!:;)&\]»”])/$&/g);
			if ($num) {
				push @{$this->{'data'}}, "At line $idx, number of entries: $num";
			}
		},
		'report' => sub ($$) {
			my ($this, $fo) = @_;
			print $fo join('', map { "\t$_\n" } @{$this->{'data'}});
		}
	},
	{
		# There should be no space as first character in the link
		'enabled' => 1,
		'name' => 'Links starting with space',
		'data' => [],
		'analyze' => sub ($$$) {
			my ($this, $ln, $idx) = @_;
			my $num = ($ln =~ s/<a [^<>]*>\s/$&/g);
			if ($num) {
				push @{$this->{'data'}}, "At line $idx, number of entries: $num";
			}
		},
		'report' => sub ($$) {
			my ($this, $fo) = @_;
			print $fo join('', map { "\t$_\n" } @{$this->{'data'}});
		}
	},
	{
		# Template for adding new tests
		'enabled' => 0,
		'name' => 'Template',
		'data' => [],
		'analyze' => sub ($$$) {
			my ($this, $ln, $idx) = @_;
			if (0) {
				push @{$this->{'data'}}, "Error at line $idx";
			}
		},
		'report' => sub ($$) {
			my ($this, $fo) = @_;
			print $fo join('', map { "\t$_\n" } @{$this->{'data'}});
		}
	},
);

################################################################################
# Main code

my $fi;
my $fo;

# Open input/output files
open($fi, '<:encoding(UTF-8)', $ARGV[0]) or die "Failed to open input file '$ARGV[0]' for reading: $!";
if ($ARGV[1]) {
	open($fo, '>:encoding(UTF-8)', $ARGV[1]) or die "Failed to open output file '$ARGV[1]' for writing: $!";
	print $fo "\x{feff}";
}
else {
	$fo = \*STDOUT;
}

# Read the input file line-by-line and call all test analyzers for each line
my $idx = 0;
while (my $ln = <$fi>) {
	++$idx;
	for my $test (@tests) {
		next if (!$test->{'enabled'});
		$test->{'analyze'}->($test, $ln, $idx);
	}
}

# Now print collected test results
for my $test (@tests) {
	next if (!$test->{'enabled'});
	print $fo "Report from test '" . $test->{'name'} . "':\n";
	$test->{'report'}->($test, $fo);
	print $fo "\n";
}

# Close files and exit
close($fi);
close($fo) if ($fo != \*STDOUT);
