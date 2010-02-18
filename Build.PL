
use strict;
use warnings;

use Module::Build;

my $build = Module::Build->new(
  module_name   => 'Finance::Bank::ID::Mandiri',
  license       => 'perl',
  dist_abstract => "Check\ your\ Bank\ Mandiri\ accounts\ from\ Perl",
  dist_name     => "Finance\-Bank\-ID\-Mandiri",
  dist_author   => [
"Steven\ Haryanto\ \<stevenharyanto\@gmail\.com\>",
  ],
  requires      => {
    "Pod::Coverage" => '0.18',
    "Test::Pod::Coverage" => '1.08',
    "Data::Dumper" => '0',
    "WWW::Mechanize" => '0',
    "Log::Any" => '0',
    "Test::More" => '0',
    "Mouse" => '0',
    "Any::Moose" => '0',
    "Finance::Bank::ID::BCA" => '0',
    "File::Slurp" => '0',
  },
  script_files => [ qw() ],
);

$build->create_build_script;
