
use strict;
use warnings;

use Module::Build 0.3601;


my %module_build_args = (
  'build_requires' => {
    'Module::Build' => '0.3601'
  },
  'configure_requires' => {
    'Module::Build' => '0.3601'
  },
  'dist_abstract' => 'Check your Bank Mandiri accounts from Perl',
  'dist_author' => [
    'Steven Haryanto <stevenharyanto@gmail.com>'
  ],
  'dist_name' => 'Finance-Bank-ID-Mandiri',
  'dist_version' => '0.16',
  'license' => 'perl',
  'module_name' => 'Finance::Bank::ID::Mandiri',
  'recommends' => {},
  'recursive_test_files' => 1,
  'requires' => {
    'Data::Dumper' => '0',
    'Data::Rmap' => '0',
    'File::Slurp' => '0',
    'Finance::Bank::ID::BCA' => '0.17',
    'Log::Any' => '0',
    'Log::Any::App' => '0.23',
    'Moo' => '0',
    'WWW::Mechanize' => '0',
    'perl' => '5.010000'
  },
  'script_files' => [
    'bin/download-mandiri'
  ]
);


my $build = Module::Build->new(%module_build_args);

$build->create_build_script;
