package Koha::Plugin::Com::RBitTechnology::GoPay;

use Modern::Perl;
use base qw(Koha::Plugins::Base);
use utf8;
use C4::Context;
use Koha::Account::Lines;
use LWP::UserAgent;
use HTTP::Headers;
use HTTP::Request::Common;
use JSON;
use HTML::Entities;
use Digest::SHA qw/hmac_sha256_hex/;

use Data::Dumper;

our $VERSION = "1.0.0";

our $metadata = {
    name            => 'Platební brána GoPay',
    author          => 'Radek Šiman',
    description     => 'Toto rozšíření poskytuje podporu online plateb s využitím brány GoPay.',
    date_authored   => '2018-01-09',
    date_updated    => '2018-01-13',
    minimum_version => '16.05',
    maximum_version => undef,
    version         => $VERSION
};

sub new {
    my ( $class, $args ) = @_;

    ## We need to add our metadata here so our base class can access it
    $args->{'metadata'} = $metadata;
    $args->{'metadata'}->{'class'} = $class;

    ## Here, we call the 'new' method for our base class
    ## This runs some additional magic and checking
    ## and returns our actual $self
    my $self = $class->SUPER::new($args);
    $self->{'ua'} = LWP::UserAgent->new();

    return $self;
}

sub configure {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    my $template = $self->get_template({ file => 'configure.tt' });
    my $phase = $cgi->param('phase');

    my $table_clients = $self->get_qualified_table_name('clients');
    my $dbh = C4::Context->dbh;

    unless ( $phase ) {
        my $query = "SELECT client_id, borrowernumber, firstname, surname, userid, secret FROM $table_clients INNER JOIN borrowers USING(borrowernumber) ORDER BY surname, firstname";
        my $sth = $dbh->prepare($query);
        $sth->execute();

        my @clients;
        while ( my $row = $sth->fetchrow_hashref() ) {
            push( @clients, $row );
        }

        print $cgi->header(-type => 'text/html',
                           -charset => 'utf-8');
        $template->param(
            goid => $self->retrieve_data('goid'),
            clientid => $self->retrieve_data('clientid'),
            clientsecret => $self->retrieve_data('clientsecret'),
            gopay_server => $self->retrieve_data('gopay_server'),
            api_clients => \@clients
        );
        print $template->output();
    }
    elsif ( $phase eq 'save_gopay' ) {
        $self->store_data(
            {
                goid => scalar $cgi->param('goid'),
                clientid => scalar $cgi->param('clientid'),
                clientsecret => scalar $cgi->param('clientsecret'),
                gopay_server => scalar $cgi->param('gopay_server'),
                last_configured_by => C4::Context->userenv->{'number'},
            }
        );
    }
    elsif ( $phase eq 'save_clients' ) {
        my $borrowernumber = $cgi->param('borrowernumber');
        my $secret = $cgi->param('secret');

        if ( $borrowernumber && $secret ) {
            my $query = "INSERT INTO $table_clients (secret, borrowernumber) VALUES (?, ?);";
            my $sth = $dbh->prepare($query);
            $sth->execute($secret, $borrowernumber);
        }
    }
    elsif ( $phase eq 'delete' ) {
        my $client_id = $cgi->param('client_id');

        if ( $client_id ) {
            my $query = "DELETE FROM $table_clients WHERE client_id = ?;";
            my $sth = $dbh->prepare($query);
            $sth->execute($client_id);
        }

        my $staffClientUrl =  C4::Context->preference('staffClientBaseURL');
        print $cgi->redirect(-uri => "$staffClientUrl/cgi-bin/koha/plugins/run.pl?class=Koha::Plugin::Com::RBitTechnology::GoPay&method=configure");
    }

    $self->go_home;
}

sub authorization {
    my ( $self, $args ) = @_;

    my @headers = [
        Content_Type => 'application/x-www-form-urlencoded',
        Accept => 'application/json'
    ];

    my $params = {
        'grant_type' =>'client_credentials',
        'scope' => 'payment-create'
    };

    my $url = $self->api . "/oauth2/token";
    my $request = POST $url, $params;
    $request->header('Accept' => 'application/json');
    $request->header('Content-Type' => 'application/x-www-form-urlencoded');
    $request->authorization_basic($self->retrieve_data('clientid'), $self->retrieve_data('clientsecret'));
    my $response = $self->{'ua'}->request($request);
    my $token  = decode_json($response->content());

    return $token->{token_type} . " " . $token->{access_token};
}

sub check_params {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    my $patron = $cgi->param('patron');
    my $return_url = $cgi->param('return_url');
    my $hmac_post = $cgi->param('hmac');

    unless ($patron && $return_url && $hmac_post) {
        $self->error({ errors => [ { message => 'Chybí jeden nebo více povinných parametrů.' } ], return_url => $return_url ? $return_url : 0 });
        return 0;
    }

    my $userid = $cgi->param('userid');
    my $password = $cgi->param('password');
    my $borrowernumber = C4::Context->userenv->{'number'};

    my $dbh = C4::Context->dbh;
    my $table_clients = $self->get_qualified_table_name('clients');
    my $query = "SELECT secret FROM $table_clients WHERE borrowernumber = ?";
    my $sth = $dbh->prepare($query);
    $sth->execute($borrowernumber);
    unless ( $sth->rows ) {
        $self->error({ errors => [ { message => "Pro přihlašovací jméno $userid neexistuje klientský záznam." } ], return_url => $return_url });
        return 0;
    }

    my $row = $sth->fetchrow_hashref();
    my $hmac = hmac_sha256_hex("$userid|$password|$patron|$return_url", $row->{'secret'});

    unless ( $hmac eq $hmac_post ) {
        $self->error({ errors => [ { message => "Neoprávněný požadavek, nepodařilo se ověřit HMAC." } ], return_url => $return_url });
        return 0;
    }

    unless ( $self->retrieve_data('goid') && $self->retrieve_data('clientid') && $self->retrieve_data('clientsecret') ) {
        $self->error({ errors => [ { message => "Chybí nastavení parametrů platební brány (GoID, Client ID, Client Secret). Dokončete prosím konfiguraci platební brány." } ], return_url => $return_url });
        return 0;
    }

    return 1;
}

sub opac_online_payment {
    my ( $self, $args ) = @_;

    return 1;
}

sub opac_online_payment_begin {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    return unless ( $self->check_params );
    my $return_url = $cgi->param('return_url');

    my $authorization = $self->authorization;
    my $staffClientUrl =  C4::Context->preference('staffClientBaseURL');

    my $table_trans = $self->get_qualified_table_name('transactions');
    my $table_items = $self->get_qualified_table_name('items');
    my $dbh = C4::Context->dbh;

    my @outstanding_fines;
    @outstanding_fines = Koha::Account::Lines->search(
        {
            borrowernumber    => scalar $cgi->param('patron'),
            amountoutstanding => { '>' => 0 },
        }
    );
    my $amount_to_pay = 0;
    my @items;
    foreach my $fine (@outstanding_fines) {
        $amount_to_pay += int(100 * $fine->amountoutstanding);
        push( @items, { name => $fine->description ? $fine->description : "Platba bez popisu", amount => int(100 * $fine->amountoutstanding) } );
    }

    unless ( scalar @items ) {
        $self->error({ errors => [ { message => 'Nebyly nalezeny žádné položky k úhradě.' } ], return_url => $return_url });
        return;
    }

    $dbh->do("START TRANSACTION");

    my $query = "INSERT INTO $table_trans (gopay_id, paid, return_url) VALUES (NULL, NULL, ?)";
    my $sth = $dbh->prepare($query);
    $sth->execute($return_url);
    my $transaction_id = $dbh->last_insert_id(undef, undef, $table_trans, 'transaction_id');

    my $params = {
        'target' => { type => "ACCOUNT", goid => $self->retrieve_data('goid') },
        'amount' => $amount_to_pay,
        'currency' => 'CZK',
        'order_number' => $transaction_id,
        'items' => \@items,
        'callback' => {
            return_url => "$staffClientUrl/cgi-bin/koha/svc/pay_api?phase=return",
            notification_url => "$staffClientUrl/cgi-bin/koha/svc/pay_api?phase=notify"
        },
    };

    my $url = $self->api . "/payments/payment";
    my $request = POST $url;
    $request->content( encode_json($params) );
    $request->header('Accept' => 'application/json');
    $request->header('Accept-Language' => 'cs');
    $request->header('Content-Type' => 'application/json');
    $request->header('Authorization' => $authorization);
    my $response = $self->{'ua'}->request($request);
    my $payment  = decode_json($response->content());

    $query = "UPDATE $table_trans SET gopay_id = ? WHERE transaction_id = ?";
    $sth = $dbh->prepare( $query );
    $sth->execute( $payment->{'id'}, $transaction_id );

    unless ( $payment->{'errors'} ) {
        my $table_items = $self->get_qualified_table_name('items');
        my @values;
        my @bindParams;

        $query = "INSERT INTO $table_items (accountlines_id, transaction_id) VALUES ";
        foreach my $fine (@outstanding_fines) {
            push( @values, "(?, ?)" );
            push( @bindParams, $fine->accountlines_id );
            push( @bindParams, $transaction_id );
        }
        $query .= join(', ', @values);
        my $sth = $dbh->prepare($query);

        for my $i (0 .. $#bindParams) {
            $sth->bind_param($i + 1, $bindParams[$i]);
        }

        $sth->execute();

        $dbh->do("COMMIT");

        print $cgi->redirect(-uri => $payment->{'gw_url'});
    }
    else {
        $self->error( { errors => $payment->{'errors'}, return_url => $return_url } );

        $dbh->do("COMMIT");     #lepsi je COMMIT, abychom videli, ze se neco delo, ROLLBACK by zahodil celou nepovedenou transakci

        return;
    }
}

sub opac_online_payment_end {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    my $dbh = C4::Context->dbh;
    my $table_items = $self->get_qualified_table_name('items');
    my $table_trans = $self->get_qualified_table_name('transactions');

    my $authorization = $self->authorization;

    my $url = $self->api . "/payments/payment/" . $cgi->param('id');
    my $request = GET $url;
    $request->header('Accept' => 'application/json');
    $request->header('Accept-Language' => 'cs');
    $request->header('Content-Type' => 'application/x-www-form-urlencoded');
    $request->header('Authorization' => $authorization);
    my $response = $self->{'ua'}->request($request);
    my $status  = decode_json($response->content());

    my $query = "SELECT transaction_id, return_url FROM $table_trans WHERE gopay_id = ?";
    my $sth = $dbh->prepare($query);
    $sth->execute( scalar $cgi->param('id') );
    unless ( $sth->rows ) {
        $self->error({ errors => [ { message => 'Platba s touto identifikací neexistuje nebo již byla uhrazena dříve.' } ] });
        return;
    }

    my $row = $sth->fetchrow_hashref();
    my $return_url = $row->{'return_url'};

    if ( $status->{'state'} eq 'PAID' ) {
        $dbh->do("START TRANSACTION");


        $query = "SELECT accountlines_id, borrowernumber, amountoutstanding FROM $table_items INNER JOIN $table_trans USING(transaction_id) INNER JOIN accountlines USING(accountlines_id) WHERE gopay_id = ? AND paid IS NULL";
        $sth = $dbh->prepare($query);
        $sth->execute( scalar $cgi->param('id') );

        my $note = "GoPay " . $cgi->param('id');
        while ( my $row = $sth->fetchrow_hashref() ) {
            my $account = Koha::Account->new( { patron_id => $row->{'borrowernumber'} } );
            $account->pay(
                {
                    amount     => $row->{'amountoutstanding'},
                    lines      => [ scalar Koha::Account::Lines->find($row->{'accountlines_id'}) ],
                    note       => $note,
                }
            );
        }

        $query = "UPDATE $table_trans SET paid = NOW() WHERE gopay_id = ?";
        $sth = $dbh->prepare($query);
        $sth->execute( scalar $cgi->param('id') );

        $dbh->do("COMMIT");

        $self->message({ text => 'Platba byla přijata. Děkujeme za úhradu.', return_url => $return_url });
    }
    else {
        $self->error({ errors => [ { message => 'Platba nebyla uhrazena.' } ], return_url => $return_url });
        return
    }

}

sub install {
    my ( $self, $args ) = @_;

    my $table_items = $self->get_qualified_table_name('items');
    my $table_trans = $self->get_qualified_table_name('transactions');
    my $table_clients = $self->get_qualified_table_name('clients');

    return C4::Context->dbh->do( "
        CREATE TABLE `$table_trans` (
            `transaction_id` int NOT NULL AUTO_INCREMENT,
            `gopay_id` bigint DEFAULT NULL,
            `created` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
            `paid` timestamp NULL DEFAULT NULL,
            `return_url` varchar(128) NOT NULL,
            PRIMARY KEY (`transaction_id`)
        ) ENGINE = INNODB DEFAULT CHARACTER SET = utf8 COLLATE = utf8_czech_ci;
        " ) &&
        C4::Context->dbh->do( "
        CREATE TABLE `$table_items` (
            `accountlines_id` int NOT NULL,
            `transaction_id` int NOT NULL,
            PRIMARY KEY (`accountlines_id`, `transaction_id`),
            CONSTRAINT `FK_gopay_accountlines` FOREIGN KEY (`accountlines_id`) REFERENCES `accountlines` (`accountlines_id`) ON UPDATE CASCADE ON DELETE CASCADE,
            CONSTRAINT `FK_gopay_transactions` FOREIGN KEY (`transaction_id`) REFERENCES `$table_trans` (`transaction_id`) ON UPDATE CASCADE ON DELETE CASCADE,
            INDEX (`accountlines_id`),
            INDEX (`transaction_id`)
        ) ENGINE = INNODB DEFAULT CHARACTER SET = utf8 COLLATE = utf8_czech_ci;" ) &&
        C4::Context->dbh->do( "
        CREATE TABLE `$table_clients` (
            `client_id` int NOT NULL AUTO_INCREMENT,
            `secret` varchar(64) NOT NULL,
            `borrowernumber` int NOT NULL,
            PRIMARY KEY (`client_id`),
            INDEX (`borrowernumber`),
            CONSTRAINT `FK_gopay_client_borrowers` FOREIGN KEY (`borrowernumber`) REFERENCES `borrowers` (`borrowernumber`) ON UPDATE CASCADE ON DELETE CASCADE
        ) ENGINE = INNODB DEFAULT CHARACTER SET = utf8 COLLATE = utf8_czech_ci;
        ");
}

sub uninstall {
    my ( $self, $args ) = @_;

    my $table_items = $self->get_qualified_table_name('items');
    my $table_trans = $self->get_qualified_table_name('transactions');
    my $table_clients = $self->get_qualified_table_name('clients');

    return C4::Context->dbh->do("DROP TABLE `$table_items`") &&
           C4::Context->dbh->do("DROP TABLE `$table_trans`") &&
           C4::Context->dbh->do("DROP TABLE `$table_clients`");
}

sub error {
    my ( $self, $args ) = @_;

    my $template = $self->get_template({ file => 'dialog.tt' });
    $template->param(
        error => 1,
        report => $args->{'errors'},
        return_url => $args->{'return_url'}
    );
    print $template->output();
}

sub message {
    my ( $self, $args ) = @_;

    my $template = $self->get_template({ file => 'dialog.tt' });
    $template->param(
        error => 0,
        report => $args->{'text'},
        return_url => $args->{'return_url'}
    );
    print $template->output();
}

sub api {
    my ( $self, $args ) = @_;
    return $self->retrieve_data('gopay_server') eq 'production' ? 'https://gate.gopay.cz/api': 'https://gw.sandbox.gopay.com/api';
}