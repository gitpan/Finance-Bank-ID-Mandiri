package Finance::Bank::ID::Mandiri;
our $VERSION = '0.05';
# ABSTRACT: Check your Bank Mandiri accounts from Perl


use Any::Moose;
use DateTime;

extends 'Finance::Bank::ID::Base';


has _variant => (is => 'rw'); # retail or pt


sub _make_readonly_inputs_rw {
    my ($self, @forms) = @_;
    for my $f (@forms) {
        for my $i (@{ $f->{inputs} }) {
            $i->{readonly} = 0 if $i->{readonly};
        }
    }
}


sub BUILD {
    my ($self, $args) = @_;

    $self->site("https://ib.bankmandiri.co.id") unless $self->site;
}


sub login {
    my ($self) = @_;

    return 1 if $self->logged_in;
    die "400 Username not supplied" unless $self->username;
    die "400 Password not supplied" unless $self->password;

    $self->logger->debug('Logging in ...');
    $self->_req(get => [$self->site . "/retail/Login.do?action=form&lang=in_ID"],
                sub {
                    my ($mech) = @_;
                    $mech->content =~ /LoginForm/ or return "no login form";
                    "";
                });
    $self->mech->set_visible(
                             $self->username,
                             $self->password,
                             [image=>"x"]);
    $self->_req(submit => [],
                sub {
                    my ($mech) = @_;
                    $mech->content =~ m!<font class="errorMessage">(.+?)</font>! and return $1;
                    $mech->content =~ /<frame\s.+Welcome/ and return; # success
                    $mech->content =~ m!<font class="alert">(\w.+?)</font>! and return $1;
                    $mech->content =~ /LoginForm/ and
                        return "submit failed, still getting login form, probably problem with image button";
                    "unknown login result page";
                });
    $self->_req(get => [$self->site . "/retail/Welcome.do?action=result"],
                sub {
                    my ($mech) = @_;
                    $mech->content !~ /SELAMAT DATANG/ and
                        return "failed getting welcome screen";
                    "";
                });
    $self->logged_in(1);
}


sub logout {
    my ($self) = @_;

    return 1 unless $self->logged_in;
    $self->logger->debug('Logging out ...');
    $self->_req(get => [$self->site . "/retail/Logout.do?action=result"]);
    $self->logged_in(0);
}

sub _parse_accounts {
    my ($self, $retrieve) = @_;
    $self->login;
    $self->logger->debug("Parsing accounts from transaction history form page ...");
    $self->_req(get => [$self->site . "/retail/TrxHistoryInq.do?action=form"]) if $retrieve;
    my $ct = $self->mech->content;
    $ct =~ /HISTORI TRANSAKSI/ or
        die "failed getting transaction history form page";
    $ct =~ m!<select name="fromAccountID">(.+?)</select>!si or
        die "failed getting the list of accounts select box (fromAccountID)";
    my $opts = $1;
    my $accts = {};
    while ($opts =~ /<option value="(\d+)">(\d+)/g) {
        $accts->{$2} = $1;
    }
    $accts;
}

# if $account is not supplied, will choose the first id
sub _get_an_account_id {
    my ($self, $account, $retrieve) = @_;
    my $accts = $self->_parse_accounts($retrieve);
    for (keys %$accts) {
        if (!$account || $_ eq $account) {
            return $accts->{$_};
        }    
    }
    die "cannot find any account ID";
}


sub list_accounts {
    my ($self) = @_;
    keys %{ $self->_parse_accounts(1) };
}


sub check_balance {
    my ($self, $account) = @_;
    my $s = $self->site;

    $self->login;
    my $acctid = $self->_get_an_account_id($account, 1);
    my $bal;
    $self->_req(get => ["$s/retail/AccountDetail.do?action=result&ACCOUNTID=$acctid"],
                sub {
                    my ($mech) = @_;
                    $mech->content =~ m!>Posisi Saldo(?:<[^>]+>\s*)*:\s*(?:<[^>]+>\s*)*(?:Rp\.)&nbsp;([0-9.]+),(\d+)<!s
                        or return "cannot grep balance in result page";
                    $bal = $self->_stripD($1)+0.01*$2;
                    "";
                });
    $bal;
}


sub get_statement {
    my ($self, %args) = @_;
    my $s = $self->site;
    my $max_days = 31;

    $self->login;

    my $mech = $self->mech;
    $self->_req(get => ["$s/retail/TrxHistoryInq.do?action=form"]);
    
    my $today = DateTime->today;
    my $end_date = $args{end_date} || $today;
    my $start_date = $args{start_date} ||
        $end_date->clone->subtract(days=>(($args{days} || $max_days)-1));

    $mech->set_fields(
        fromAccountID => $self->_get_an_account_id($args{account}, 0),
        fromDay   => $start_date->day,
        fromMonth => $start_date->month,
        fromYear  => $start_date->year,
        toDay     => $end_date->day,
        toMonth   => $end_date->month,
        toYear    => $end_date->year,
    );

    # to shut up HTML::Form's read-only warning
    $self->_make_readonly_inputs_rw($mech->forms);

    $mech->set_fields(action => "result");

    $self->_req(submit => [],
                sub {
                    my ($mech) = @_;
                    $mech->content =~ /saldo/i or return "failed getting statement";
                    "";
                });

    my ($res, $h, $stmt) = $self->parse_statement($self->mech->content);
    return if $res != 200;
    $stmt;
}


sub _ps_detect {
    my ($self, $page) = @_;
    if ($page =~ /(?:^|"header">)HISTORI TRANSAKSI/m) {
        $self->_variant('retail');
        return '';
    } elsif ($page =~ /^CMS-Mandiri/ms) {
        $self->_variant('pt');
        return '';
    } else {
        return "No Mandiri statement page signature found";
    }
}

sub _ps_get_metadata {
    my ($self, @args) = @_;
    if ($self->_variant eq 'retail') {
        $self->_ps_get_metadata_retail(@args);
    } elsif ($self->_variant eq 'pt') {
        $self->_ps_get_metadata_pt(@args);
    } else {
        return "internal bug: _variant not yet set";
    }
}

sub _ps_get_metadata_retail {
    my ($self, $page, $stmt) = @_;

    unless ($page =~ /Tampilkan Berdasarkan(?:\s+|(?:<[^>]+>\s*)*):(?:\s+|(?:<[^>]+>\s*)*)Tanggal(?:\s+|(?:<[^>]+>\s*)*)Urutkan Berdasarkan(?:\s+|(?:<[^>]+>\s*)*):(?:\s+|(?:<[^>]+>\s*)*)Mulai dari yang kecil/s) {
      return "currently only support descending order ('Mulai dari yang kecil')";
    }

    my $adv1 = "maybe statement format changed or input incomplete";

    unless ($page =~ /(?:^|>)Nomor Rekening(?:\s+|(?:<[^>]+>\s*)*):(?:\s+|(?:<[^>]+>\s*)*)(\d+) (Rp\.|[A-Z]+)/m) {
      return "can't get account number, $adv1";
    }
    $stmt->{account} = $1;
    $stmt->{currency} = ($2 eq 'Rp.' ? 'IDR' : $2);

    # check completeness, because the latest transactions are displayed first
    unless ($page =~ /(?:|>)Saldo Akhir(?:\s+|(?:<[^>]+>\s*)*):(?:\s+|(?:<[^>]+>\s*)*)\d/m) {
      return "statement page probably truncated in the middle, try to input the whole page";
    }

    # along with their common misspellings, these are not in DateTime::Locale
    my %shortmon_id = (Jan=>1, Feb=>2, Peb=>2, Mar=>3, Apr=>4, Mei=>5, Jun=>6,
                       Jul=>7, Agu=>8, Agt=>8, Agus=>8, Agust=>8, Sep=>9,
                       Sept=>9, Okt=>10, Nov=>11, Nop=>11, Des=>12);
    my %shortmon_en = (Jan=>1, Feb=>2, Mar=>3, Apr=>4, May=>5, Jun=>6,
                       Jul=>7, Aug=>8, Sep=>9, Oct=>10, Nov=>11, Dec=>12);
    my %shortmon = (%shortmon_id, %shortmon_en);
    my $shortmon_re = join "|", keys(%shortmon);
    $shortmon_re = qr/(?:$shortmon_re)/;

    unless ($page =~ m!(?:^|>)Periode Transaksi(?:\s+|(?:<[^>]+>\s*)*):(?:\s+|(?:<[^>]+>\s*)*)(\d\d?) ($shortmon_re) (\d\d\d\d)\s*-\s*(\d\d?) ($shortmon_re) (\d\d\d\d)!m) {
      return "can't get period, $adv1";
    }
    return "can't parse month name: $2" unless $shortmon{$2};
    return "can't parse month name: $5" unless $shortmon{$5};
    $stmt->{start_date} = DateTime->new(day=>$1, month=>$shortmon{$2}, year=>$3);
    $stmt->{end_date}   = DateTime->new(day=>$4, month=>$shortmon{$5}, year=>$6);

    # for safety, but i forgot why
    my $today = DateTime->today;
    if (DateTime->compare($stmt->{start_date}, $today) == 1) {
        $stmt->{start_date} = $today;
    }
    if (DateTime->compare($stmt->{end_date}, $today) == 1) {
        $stmt->{end_date} = $today;
    }

    unless ($page =~ /(?:^|>)Total Kredit(?:\s+|(?:<[^>]+>\s*)*):(?:\s+|(?:<[^>]+>\s*)*)([0-9,.]+)[.,](\d\d)/m) {
      return "can't get total credit, $adv1";
    }
    $stmt->{_total_credit_in_stmt} = $self->_stripD($1) + 0.01*$2;

    unless ($page =~ /(?:^|>)Total Debet(?:\s+|(?:<[^>]+>\s*)*):(?:\s+|(?:<[^>]+>\s*)*)([0-9,.]+)[.,](\d\d)/m) {
      return "can't get total debit, $adv1";
    }
    $stmt->{_total_debit_in_stmt} = $self->_stripD($1) + 0.01*$2;

    "";
}

sub _ps_get_metadata_pt {
    my ($self, $page, $stmt) = @_;

    unless ($page =~ /^- End Of Statement -/m) {
        return "statement page truncated in the middle, please input the whole page";
    }

    unless ($page =~ /^Account No\s*:\s*(\d+)/m) {
        return "can't get account number";
    }
    $stmt->{account} = $1;

    unless ($page =~ /^Account Name\s*:\s*(.+?)[\012\015]/m) {
        return "can't get account holder";
    }
    $stmt->{account_holder} = $1;

    unless ($page =~ /^Currency\s*:\s*([A-Z]+)/m) {
        return "can't get account holder";
    }
    $stmt->{currency} = $1;

    my $adv1 = "maybe statement format changed, or input incomplete";

    unless ($page =~ m!Period\s*:\s*(\d\d?)/(\d\d?)/(\d\d\d\d)\s*-\s*(\d\d?)/(\d\d?)/(\d\d\d\d)!m) {
        return "can't get statement period, $adv1";
    }
    $stmt->{start_date} = DateTime->new(day=>$1, month=>$2, year=>$3);
    $stmt->{end_date}   = DateTime->new(day=>$4, month=>$5, year=>$6);

    # for safety, but i forgot why
    my $today = DateTime->today;
    if (DateTime->compare($stmt->{start_date}, $today) == 1) {
        $stmt->{start_date} = $today;
    }
    if (DateTime->compare($stmt->{end_date}, $today) == 1) {
        $stmt->{end_date} = $today;
    }

    # Mandiri sucks, doesn't provide total credit/debit in statement
    my $n = 0;
    while ($page =~ m!^\d\d?/\d\d?\s!mg) { $n++ }
    $stmt->{_num_tx_in_stmt} = $n;
    "";
}

sub _ps_get_transactions {
    my ($self, @args) = @_;
    if ($self->_variant eq 'retail') {
        $self->_ps_get_transactions_retail(@args);
    } elsif ($self->_variant eq 'pt') {
        $self->_ps_get_transactions_pt(@args);
    } else {
        return "internal bug: _variant not yet set";
    }
}

sub _ps_get_transactions_retail {
    my ($self, $page, $stmt) = @_;

    my @e;
    # text version
    while ($page =~ m!^(\d\d)/(\d\d)/(\d\d\d\d)\s*\t\s*((?:[^\t]|\n)*?)\s*\t\s*([0-9.]+),(\d\d)\s*\t\s*([0-9.]+),(\d\d)!mg) {
        push @e, {day=>$1, mon=>$2, year=>$3, desc=>$4, db=>$5, dbf=>$6, cr=>$7, crf=>$8};
    }
    if (!@e) {
        # HTML version
        while ($page =~ m!^\s+<tr[^>]*>\s*
<td[^>]+> (\d\d)/(\d\d)/(\d\d\d\d) \s* </td>\s*
<td[^>]+> ((?:[^\t]|\n)*?)     </td>\s*
<td[^>]+> ([0-9.]+),(\d\d)     </td>\s*
<td[^>]+> ([0-9.]+),(\d\d)     </td>\s*
</tr>!smxg) {
          push @e, {day=>$1, mon=>$2, year=>$3, desc=>$4, db=>$5, dbf=>$6, cr=>$7, crf=>$8};
        }
        for (@e) { $_->{desc} =~ s!<br ?/?>!\n!ig }
    }

    # when they say "kecil ke besar" they actually mean showing the latest transactions first
    @e = reverse @e;

    my @tx;
    my @skipped_tx;
    my $seq;
    my $i = 0;
    my $last_date;
    for my $e (@e) {
        $i++;
        my $tx = {};
        $tx->{date} = DateTime->new(day=>$e->{day}, month=>$e->{mon}, year=>$e->{year});
        $tx->{description} = $e->{desc};
        my $db = $self->_stripD($e->{db}) + 0.01*$e->{dbf};
        my $cr = $self->_stripD($e->{cr}) + 0.01*$e->{crf};
        if ($db == 0) { $tx->{amount} = $cr }
        elsif ($cr == 0) { $tx->{amount} = -$db }
        else { return "check failed in tx#$i: debit and credit both exist" }

        if (!$last_date || DateTime->compare($last_date, $tx->{date})) {
            $seq = 1;
            $last_date = $tx->{date};
        } else {
            $seq++;
        }
        $tx->{seq} = $seq;

        # skip reversal pair (tx + tx') because tx' is just a correction
        # reversal and the pair will be removed anyway by Mandiri in the next
        # day's statement. currently can only handle pair in the same day and in
        # succession.
        if ($seq > 1 && $tx->{description} =~ /^Reversal / &&
            $tx->{amount} == -$tx[-1]{amount}) {
            push @skipped_tx, pop(@tx);
            push @skipped_tx, $tx;
            $seq -= 2;
        } else {
            push @tx, $tx;
        }
    }
    $stmt->{transactions} = \@tx;
    $stmt->{skipped_transactions} = \@skipped_tx;
    "";
}

sub _ps_get_transactions_pt {
    my ($self, $page, $stmt) = @_;

    if ($page =~ /<br|<p/i) {
        return "sorry, HTML version is not yet supported";
    }

    my @e;
    # text version
    while ($page =~ m!^(\d\d?)/(\d\d?)\s+(\d\d?)/(\d\d?)\s+(.*?)\t(.*)\s+([0-9.]+),(\d\d) ([CD])\s+([0-9.]+),(\d\d) ([CD])!mg) {
        # date (=tgl transaksi), value date (=tgl pembukuan?), description ("Setor Tunai"), description 2 ("DARI Andi Budi"), amount, balance
        push @e, {daytx=>$1, montx=>$2, daybk=>$3, monbk=>$4, desc1=>$5, desc2=>$6,
                  amt=>$7, amtf=>$8, amtc=>$9, bal=>$10, balf=>11, balc=>12};
    }

    my @tx;
    my $seq;
    my $last_date;
    for my $e (@e) {
        my $tx = {};
        $tx->{tx_date} = DateTime->new(
            day   => $e->{daytx},
            month => $e->{montx},
            year  => (($e->{montx} <  $stmt->{start_date}->mon ||
                       $e->{montx} == $stmt->{start_date}->mon && $e->{daytx} == $stmt->{start_date}->day) ?
                      $stmt->{end_date}->year : $stmt->{start_date}->year)
        );
        $tx->{book_date} = DateTime->new(
            day   => $e->{daybk},
            month => $e->{monbk},
            year  => (($e->{monbk} <  $stmt->{start_date}->mon ||
                       $e->{monbk} == $stmt->{start_date}->mon && $e->{daybk} == $stmt->{start_date}->day) ?
                      $stmt->{end_date}->year : $stmt->{start_date}->year)
        );
        $tx->{date} = $tx->{book_date};

        $tx->{amount}  = ($e->{amtc} eq 'C' ? 1:-1) * $self->_stripD($e->{amt}) + 0.01 * $e->{amtf};
        $tx->{balance} = ($e->{balc} eq 'C' ? 1:-1) * $self->_stripD($e->{bal}) + 0.01 * $e->{balf};
        $tx->{description} = $e->{desc1} . "\n" . $e->{desc2};

        if (!$last_date || DateTime->compare($last_date, $tx->{date})) {
            $seq = 1;
            $last_date = $tx->{date};
        } else {
            $seq++;
        }
        $tx->{seq} = $seq;

        push @tx, $tx;
    }
    $stmt->{transactions} = \@tx;
    "";
}

__PACKAGE__->meta->make_immutable;
no Any::Moose;
1;

__END__
=pod

=head1 NAME

Finance::Bank::ID::Mandiri - Check your Bank Mandiri accounts from Perl

=head1 VERSION

version 0.05

=head1 SYNOPSIS

    use Finance::Bank::ID::Mandiri;

    # FBI::Mandiri uses Log::Any. to show logs, use something like:
    use Log::Log4perl qw(:easy);
    use Log::Any::Adapter;
    Log::Log4perl->easy_init($DEBUG);
    Log::Any::Adapter->set('Log4perl');

    my $ibank = Finance::Bank::ID::Mandiri->new(
        username => '....', # optional if you're only using parse_statement()
        password => '....', # idem
    );

    eval {
        $ibank->login(); # dies on error

        my $accts = $ibank->list_accounts();

        my $bal = $ibank->check_balance($acct); # $acct is optional

        my $stmt = $ibank->get_statement(
            account    => ..., # opt, default account will be used if not specified
            days       => 31,  # opt
            start_date => DateTime->new(year=>2009, month=>10, day=>6),
                               # opt, takes precedence over 'days'
            end_date   => DateTime->today, # opt, takes precedence over 'days'
        );

        print "Transactions: ";
        for my $tx (@{ $stmt->{transactions} }) {
            print "$tx->{date} $tx->{amount} $tx->{description}\n";
        }
    };

    # remember to call this, otherwise you will have trouble logging in again
    # for some time
    if ($ibank->logged_in) { $ibank->logout() }

    # utility routines
    my $stmt = $ibank->parse_statement($html_or_copy_pasted_text);

Also see the examples/ subdirectory in the distribution for a sample script using
this module.

=head1 DESCRIPTION

This module provide a rudimentary interface to the web-based online banking
interface of the Indonesian B<Bank Mandiri> at
https://ib.bankmandiri.co.id. You will need either L<Crypt::SSLeay> or
L<IO::Socket::SSL> installed for HTTPS support to work. L<WWW::Mechanize> is
required but you can supply your own mech-like object.

This module can only login to the retail/personal version of the site and not
the corporate/PT/CMS version as the later requires IE. But this module can
parse statement page from both versions (for CMS version, only text version
[copy paste result] is currently supported and not HTML).

Warning: This module is neither offical nor is it tested to be 100% save!
Because of the nature of web-robots, everything may break from one day to the
other when the underlying web interface changes.

=head1 WARNING

This warning is from Simon Cozens' C<Finance::Bank::LloydsTSB>, and seems just
as apt here.

This is code for B<online banking>, and that means B<your money>, and that means
B<BE CAREFUL>. You are encouraged, nay, expected, to audit the source of this
module yourself to reassure yourself that I am not doing anything untoward with
your banking data. This software is useful to me, but is provided under B<NO
GUARANTEE>, explicit or implied.

=head1 ERROR HANDLING AND DEBUGGING

Most methods die() when encountering errors, so you can use eval() to trap them.

This module uses L<Log::Any>, so you can see more debugging statements on 
your screen, log files, etc.

Full response headers and bodies are dumped to a separate logger. See 
documentation on C<new()> below and the sample script in examples/ subdirectory
in the distribution.

=head1 ATTRIBUTES

=head1 METHODS

=head2 new(%args)

Create a new instance. %args keys:

=over

=item * username

Optional if you are just using utility methods like C<parse_statement()> and not
C<login()> etc.

=item * password

Optional if you are just using utility methods like C<parse_statement()> and not
C<login()> etc.

=item * mech

Optional. A L<WWW::Mechanize>-like object. By default this module instantiate a
new WWW::Mechanize object to retrieve web pages, but if you want to use a
custom/different one, you are allowed to do so here. Use cases include: you want
to retry and increase timeout due to slow/unreliable network connection (using
L<WWW::Mechanize::Plugin::Retry>), you want to slow things down using
L<WWW::Mechanize::Sleepy>, you want to use IE engine using
L<Win32::IE::Mechanize>, etc.

=item * logger

Optional. You can supply a L<Log::Any>-like object here. If not specified,
this module will use a default logger.

=item * logger_dump

Optional. You can supply a L<Log::Any>-like object here. This is just
like C<logger> but this module will log contents of response bodies
here for debugging purposes. You can use with something like
L<Log::Dispatch::Dir> to save web pages more conveniently as separate
files.

=back

=head2 login()

Login to the net banking site. You actually do not have to do this explicitly as
login() is called by other methods like C<check_balance()> or
C<get_statement()>.

If login is successful, C<logged_in> will be set to true and subsequent calls to
C<login()> will become a no-op until C<logout()> is called.

Dies on failure.

=head2 logout()

Logout from the net banking site. You need to call this at the end of your
program, otherwise the site will prevent you from re-logging in for some time
(e.g. 10 minutes).

If logout is successful, C<logged_in> will be set to false and subsequent calls
to C<logout()> will become a no-op until C<login()> is called.

Dies on failure.

=head2 list_accounts()

=head2 check_balance([$acct])

=head2 get_statement(%args)

Get account statement. %args keys:

=over

=item * account

Optional. Select the account to get statement of. If not specified, will use the
already selected account.

=item * days

Optional. Number of days between 1 and 31. If days is 1, then start date and end
date will be the same. Default is 31.

=item * start_date

Optional. Default is end_date - days.

=item * end_date

Optional. Default is today (or some 1+ days from today if today is a
Saturday/Sunday/holiday, depending on the default value set by the site's form).

=back

=head2 parse_statement($html_or_text, %opts)

Given the HTML/copy-pasted text of the account statement results page, parse it
into structured data:

 $stmt = {
    start_date     => $start_dt, # a DateTime object
    end_date       => $end_dt,   # a DateTime object
    account_holder => STRING,
    account        => STRING,    # account number
    currency       => STRING,    # 3-digit currency code
    transactions   => [
        # first transaction
        {
          date        => $dt, # a DateTime object, book date ("tanggal pembukuan")
          seq         => INT, # a number >= 1 which marks the sequence of transactions for the day
          amount      => REAL, # a real number, positive means credit (deposit), negative means debit (withdrawal)
          description => STRING,
          is_pending  => BOOL,
          branch      => STRING, # a 4-digit branch/ATM code
          balance     => REAL,
        },
        # second transaction
        ...
    ]
 }

If parsing failed, will return undef.

In list context, this method will return HTTP-style response instead:

 ($status, $err_details, $stmt)

C<$status> is 200 if successful or some other 3-letter code if parsing failed.
C<$stmt> is the result (structure as above, or undef if parsing failed).

=head1 AUTHOR

  Steven Haryanto <stevenharyanto@gmail.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2010 by Steven Haryanto.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

