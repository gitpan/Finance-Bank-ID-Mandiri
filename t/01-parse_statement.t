#!perl -Tw

use strict;
use Test::More tests => (3*10 + 1*12);
use DateTime;
use File::Slurp;
use FindBin '$Bin';
use Log::Log4perl qw(:easy);
use Finance::Bank::ID::Mandiri;

Log::Log4perl->easy_init($ERROR);

my $ibank = Finance::Bank::ID::Mandiri->new();

for my $f (
    ["stmt1.html", "personal, html"],
    ["stmt1.opera10linux.txt", "personal, txt, opera10linux"],
    ["stmt1.ff35linux.txt", "personal, txt, ff35linux"]) {
    my ($status, $error, $stmt) = $ibank->parse_statement(scalar read_file("$Bin/data/$f->[0]"));
    #print "status=$status, error=$error\n";

    # metadata
    is($stmt->{account}, "1234567890123", "$f->[1] (account)");
    is(DateTime->compare($stmt->{start_date},
                         DateTime->new(year=>2009, month=>8, day=>13)),
       0, "$f->[1] (start_date)");
    is(DateTime->compare($stmt->{end_date},
                         DateTime->new(year=>2009, month=>8, day=>13)),
       0, "$f->[1] (end_date)");
    is($stmt->{currency}, "IDR", "$f->[1] (currency)");

    # transactions
    is(scalar(@{ $stmt->{transactions} }), 2, "$f->[1] (num tx)");
    is(DateTime->compare($stmt->{transactions}[0]{date},
                         DateTime->new(year=>2009, month=>8, day=>13)),
       0, "$f->[1] (tx0 date)");
    # remember, order is reversed
    is($stmt->{transactions}[0]{amount}, -222222, "$f->[1] (tx0 amount)");
    is($stmt->{transactions}[1]{amount}, 111111, "$f->[1] (amount)");
    is($stmt->{transactions}[0]{seq}, 1, "$f->[1] (tx0 seq)");
    is($stmt->{transactions}[1]{seq}, 2, "$f->[1] (seq)");
}

for my $f (
    ["stmt2.txt", "bisnis, txt"],) {
    my ($status, $error, $stmt) = $ibank->parse_statement(scalar read_file("$Bin/data/$f->[0]"));
    #print "status=$status, error=$error\n";

    # metadata
    is($stmt->{account}, "1234567890123", "$f->[1] (account)");
    is($stmt->{account_holder}, "MAJU MUNDUR", "$f->[1] (account_holder)");
    is(DateTime->compare($stmt->{start_date},
                         DateTime->new(year=>2009, month=>8, day=>10)),
       0, "$f->[1] (start_date)");
    is(DateTime->compare($stmt->{end_date},
                         DateTime->new(year=>2009, month=>8, day=>15)),
       0, "$f->[1] (end_date)");
    is($stmt->{currency}, "IDR", "$f->[1] (currency)");

    # transactions
    is(scalar(@{ $stmt->{transactions} }), 3, "$f->[1] (num tx)");
    is(DateTime->compare($stmt->{transactions}[0]{date},
                         DateTime->new(year=>2009, month=>8, day=>10)),
       0, "$f->[1] (tx0 date)");
    is($stmt->{transactions}[0]{amount}, 111111, "$f->[1] (tx0 amount)");
    is($stmt->{transactions}[0]{seq}, 1, "$f->[1] (tx0 seq)");

    is($stmt->{transactions}[1]{amount}, -2000, "$f->[1] (debit)");

    is($stmt->{transactions}[1]{seq}, 1, "$f->[1] (seq 1)");
    is($stmt->{transactions}[2]{seq}, 2, "$f->[1] (seq 2)");
}
