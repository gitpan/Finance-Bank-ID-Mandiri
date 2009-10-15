use inc::Module::Install;

name     'Finance-Bank-ID-Mandiri';
all_from 'lib/Finance/Bank/ID/Mandiri.pm';
author   'Steven Haryanto <stevenharyanto@gmail.com>';
license  'perl';

build_requires 'Test::More';

test_requires 'File::Slurp';

requires 'Finance::Bank::ID::BCA';

auto_install;

WriteAll;
