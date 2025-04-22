package SLNP::Backend;

# Copyright 2021 (C) Theke Solutions
# Copyright 2018-2021 (C) LMSCLoud GmbH
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# This program comes with ABSOLUTELY NO WARRANTY;

use Modern::Perl;

use Carp;
use Clone qw( clone );
use JSON  qw( to_json );
use MARC::Record;
use Scalar::Util qw(blessed);
use Try::Tiny;
use URI::Escape;
use XML::LibXML;
use YAML::XS;

use C4::Biblio qw( AddBiblio DelBiblio );
use C4::Context;
use C4::Letters qw(GetPreparedLetter);
use C4::Members::Messaging;
use C4::Reserves qw(AddReserve);

use Koha::Biblios;
use Koha::Database;
use Koha::DateUtils qw(dt_from_string output_pref);
use Koha::ILL::Request::Config;
use Koha::Items;
use Koha::Libraries;
use Koha::Patron::Attributes;
use Koha::Patron::Categories;
use Koha::Patrons;

use Koha::Plugin::Com::Theke::SLNP;
use SLNP::Exceptions;

=head1 NAME

SLNP::Backend - Koha ILL Backend: SLNP

=head1 SYNOPSIS

Koha ILL implementation for the "SLNP" backend.

Some library consortia in Germany run ILL servers that use SLNP (Simple Library Network Protocol) 
for communication with the integrated library management systems.
ZFL is the abbreviation for 'Zentrale Fernleihe' (central interlibrary loan).

=head1 DESCRIPTION

SLNP (TM) (Simple Library Network Protocol) is a TCP network socket based protocol 
designed and introduced by the company Sisis Informationssysteme GmbH (later a part of OCLC) 
for their library management system SISIS-SunRise (TM).
This protocol supports the bussiness processes of libraries.
A subset of SLNP that enables the communication required for regional an national ILL (Inter Library Loan) processes
has been published by Sisis Informationssysteme GmbH as basis for 
connection of library management systems to ILL servers that use SLNP.
Sisis Informationssysteme GmbH / OCLC owns all rights to SLNP.
SLNP is a registered trademark of Sisis Informationssysteme GmbH / OCLC.

This ILL backend provides a simple method to handle Interlibrary Loan requests that are initiated by an regional ILL server using the SLNP protocol.
The additional service 'ILLZFLServerKoha' manages the communication with the regional ILL server and will insert records in tables illrequests and illrequestattributes by calling the 'create' method of SLNP. 
The remaining features of this ILL backend are accessible via the standard ILL framework in the Koha staff interface.

=head1 API

=head2 Class methods

=head3 new

  my $plugin  = Koha::Plugin::Com::Theke::SLNP->new;
  my $backend = SLNP::Backend->new( { plugin => $plugin } );

Constructor for the SLNP ILL backend.

=cut

sub new {
    my ( $class, $params ) = @_;

    SLNP::Exception::MissingParameter->throw( param => 'plugin' )
        unless $params->{plugin} && ref( $params->{plugin} ) eq 'Koha::Plugin::Com::Theke::SLNP';

    my $config  = $params->{plugin}->configuration;
    my $strings = $params->{plugin}->get_strings;

    my $self = {
        configuration => $config,
        framework     => $config->{default_framework} // 'FA',
        logger        => $params->{logger},
        plugin        => $params->{plugin},
        status_graph  => $strings->{status_graph},
        strings       => $strings,
        templates     => $params->{templates},
    };

    bless( $self, $class );
    return $self;
}

=head3 name

Return the name of this backend.

=cut

sub name {
    return "SLNP";
}

=head3 bundle_path

    my $path = $backend->bundle_path();

Returns the backend's defined template path.
FIXME: Review when consensus is reached on https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=39031

=cut

sub bundle_path {
    my ($self) = @_;
    return $self->{plugin}->bundle_path . "/templates/";
}

=head3 _config

    my $config = $slnp_backend->_config($config);
    my $config = $slnp_backend->_config;

Getter/Setter for our config object.

=cut

sub _config {
    my ( $self, $config ) = @_;

    $self->{config} = $config if ($config);

    return $self->{config};
}

=head3 status_graph

=cut

sub status_graph {
    my ($self) = @_;
    return {
        REQ => {
            prev_actions   => [],
            id             => 'REQ',
            name           => $self->{status_graph}->{REQ}->{name},    #'Bestellt',
            ui_method_name => undef,
            method         => undef,
            next_actions   => [ 'RECVD', 'NEGFLAG', 'CANC' ],
            ui_method_icon => '',
        },

        CANC => {
            prev_actions   => ['REQ'],
            id             => 'CANC',
            name           => $self->{status_graph}->{CANC}->{name},
            ui_method_name => $self->{status_graph}->{CANC}->{ui_method_name},
            method         => 'cancel',
            next_actions   => ['SLNP_COMP'],
            ui_method_icon => 'fa-times',
        },

        RECVD => {
            prev_actions   => ['REQ'],
            id             => 'RECVD',
            name           => $self->{status_graph}->{RECVD}->{name},
            ui_method_name => $self->{status_graph}->{RECVD}->{ui_method_name},
            method         => 'receive',
            next_actions   => [ 'RECVDUPD', 'SLNP_COMP', 'SLNP_LOST_COMP', 'SENT_BACK' ],
            ui_method_icon => 'fa-download',
        },

        RECVDUPD => {    # Pseudo status
            prev_actions   => ['RECVD'],
            id             => 'RECVDUPD',
            name           => $self->{status_graph}->{RECVDUPD}->{name},
            ui_method_name => $self->{status_graph}->{RECVDUPD}->{ui_method_name},
            method         => 'update',
            next_actions   => [],                                                    # really RECVD
            ui_method_icon => 'fa-pencil',
        },

        CHK => {
            prev_actions   => [],
            id             => 'CHK',
            name           => $self->{status_graph}->{CHK}->{name},
            ui_method_name => '',
            method         => '',
            next_actions   => [],
            ui_method_icon => 'fa-check',
        },

        RET => {
            prev_actions   => [],
            id             => 'RET',
            name           => $self->{status_graph}->{RET}->{name},
            ui_method_name => '',
            method         => '',
            next_actions   => [ 'SLNP_COMP', 'SENT_BACK', 'SLNP_LOST_COMP' ],
            ui_method_icon => 'fa-check',
        },

        NEGFLAG => {
            prev_actions   => ['REQ'],
            id             => 'NEGFLAG',
            name           => $self->{status_graph}->{NEGFLAG}->{name},
            ui_method_name => $self->{status_graph}->{NEGFLAG}->{ui_method_name},
            method         => 'cancel_unavailable',
            next_actions   => [],
            ui_method_icon => 'fa-times',
        },

        SENT_BACK => {
            prev_actions   => [ 'RET', 'RECVD' ],
            id             => 'SENT_BACK',
            name           => $self->{status_graph}->{SENT_BACK}->{name},
            ui_method_name => $self->{status_graph}->{SENT_BACK}->{ui_method_name},
            method         => 'return_to_library',
            next_actions   => ['SLNP_COMP'],
            ui_method_icon => 'fa-truck',
        },

        SLNP_COMP => {    # Intermediate status for handling cleanup
            prev_actions   => ['RET'],
            id             => 'SLNP_COMP',
            name           => $self->{status_graph}->{SLNP_COMP}->{name},
            ui_method_name => $self->{status_graph}->{SLNP_COMP}->{ui_method_name},
            method         => 'slnp_mark_completed',
            next_actions   => [],
            ui_method_icon => 'fa-check',
        },

        SLNP_LOST => {
            prev_actions   => [],
            id             => 'SLNP_LOST',
            name           => $self->{status_graph}->{SLNP_LOST}->{name},
            ui_method_name => '',
            method         => '',
            next_actions   => ['SLNP_LOST_COMP'],
            ui_method_icon => '',
        },

        SLNP_LOST_COMP => {
            prev_actions   => [ 'SLNP_LOST', 'RET', 'RECVD' ],
            id             => 'SLNP_LOST_COMP',
            name           => $self->{status_graph}->{SLNP_LOST_COMP}->{name},
            ui_method_name => $self->{status_graph}->{SLNP_LOST_COMP}->{ui_method_name},
            method         => 'mark_lost',
            next_actions   => ['SLNP_COMP'],
            ui_method_icon => 'fa-exclamation-circle',
        },

        COMP => {
            prev_actions   => ['SLNP_COMP'],
            id             => 'COMP',
            name           => $self->{status_graph}->{COMP}->{name},
            ui_method_name => $self->{status_graph}->{COMP}->{ui_method_name},
            method         => '',
            next_actions   => [],
            ui_method_icon => 'fa-check',
        },

        ## Lending workflow
        L_REQ => {
            prev_actions   => [],
            id             => 'L_REQ',
            name           => $self->{status_graph}->{L_REQ}->{name},
            ui_method_name => undef,
            method         => undef,
            next_actions   => ['COMP'],
            ui_method_icon => '',
        },
    };
}

=head3 capabilities

    $capability = $backend->capabilities($name);

Return the sub implementing a capability selected by I<$name>, or 0 if that
capability is not implemented.

=cut

# sub capabilities {
#     my ( $self, $name ) = @_;
#     my ($query) = @_;
#     my $capabilities = {

# # experimental, general access, not used yet (usage: my $duedate = $illrequest->_backend_capability( "getIllrequestattributes", [$illrequest,["duedate"]] );)
#         getIllrequestattributes => sub { $self->getIllrequestattributes(@_); },

#         # used capabilities:
#         getIllrequestDateDue   => sub { $self->getIllrequestDateDue(@_); },
#         isShippingBackRequired => sub { $self->isShippingBackRequired(@_); },
#         itemCheckedOut         => sub { $self->itemCheckedOut(@_); },
#         itemCheckedIn          => sub { $self->itemCheckedIn(@_); },
#         itemLost               => sub { $self->itemLost(@_); },
#         isReserveFeeAcceptable => sub { $self->isReserveFeeAcceptable(@_); },
#         sortAction             => sub { $self->sortAction(@_); }
#     };
#     return $capabilities->{$name};
# }

=head3 metadata

Return a hashref containing canonical values from the key/value
illrequestattributes table.
Theese canonical values are used in the table view and record view of the ILL framework
und so can not be renamed without adaptions.

=cut

sub metadata {
    my ( $self, $request ) = @_;

    my %map = (
        'Article_author'  => 'article_author',  # used alternatively to 'Author'
        'Article_title'   => 'article_title',   # used alternatively to 'Title'
        'Author'          => 'author',
        'ISBN'            => 'isbn',
        'Order ID'        => 'zflorderid',
        'Title'           => 'title',
        'Lending_library' => 'lending_library',
        'Sigel_lending_library' => 'sigel_lending_library',
    );

    my %attr;
    for my $k ( keys %map ) {
        my $v = $request->extended_attributes->find( { type => $map{$k} } );
        $attr{$k} = $v->value if defined $v;
    }
    if ( $attr{Article_author} ) {
        if ( length( $attr{Article_author} ) ) {
            $attr{Author} = $attr{Article_author};
        }
        delete $attr{Article_author};
    }
    if ( $attr{Article_title} ) {
        if ( length( $attr{Article_title} ) ) {
            $attr{Title} = $attr{Article_title};
        }
        delete $attr{Article_title};
    }

    # lending library is the borrowernumber
    if ( $attr{Lending_library} && length( $attr{Lending_library} ) ) {
        my $lending_library = Koha::Patrons->find( $attr{Lending_library} );
        if ($lending_library) {
            $attr{Lending_library} =
                $lending_library->surname . " "
              . $lending_library->firstname
              . (
                $lending_library->othernames
                ? " (" . $lending_library->othernames . ")"
                : ""
              );
        }
    }
    elsif ( $attr{Sigel_lending_library} ) {
        # Sigel_lending_library is the original value from SLNP
        # show unless lending_library is set
        $attr{Lending_library} = $attr{Sigel_lending_library};
    }

    delete( $attr{Sigel_lending_library} ) if ( $attr{Sigel_lending_library} );

    return \%attr;
}


=head3 create

    my $response = $slnp_backend->create( $params );

Checks values in $params and inserts an illrequests record.
The values in $params normally are filled by SLNPFLBestellung.pm based on the request parameters of the received SLNP command 'SLNPFLBestellung'.
Returns an ILL backend standard response for the create method call.

=cut

sub create {
    my ( $self, $params ) = @_;
    my $stage = $params->{other}->{stage};

    my $backend_result = {
        backend => $self->name,
        method  => 'create',
        stage   => $stage,
        error   => 0,
        status  => '',
        message => '',
        value   => {}
    };

    $backend_result->{strings} = $params->{request}->_backend->{strings}->{staff_create};

    # Initiate process stage is dummy for SLNP
    if ( !$stage || $stage eq 'init' ) {

        # ILL request is created by the external server sending
        # a SLNPFLBestellung request, so no manual handling at this stage
        # Pass useful information for rendering the create page
        $backend_result->{value}->{portal_url} = $self->{configuration}->{portal_url} // 'https://fix.me';
    }

    # Validate SLNP request parameter values and insert new ILL request in DB
    elsif ( $stage eq 'commit' ) {

        # Search for the patron using the passed cardnumber
        my $patron = Koha::Patrons->find( { cardnumber => $params->{other}->{attributes}->{cardnumber} } );
        unless ($patron) {
            $patron = Koha::Patrons->find( { userid => $params->{other}->{attributes}->{cardnumber} } );
        }

        SLNP::Exception::PatronNotFound->throw(
            "Patron not found with cardnumber (or userid): " . $params->{other}->{attributes}->{cardnumber} )
            unless $patron;

        $params->{other}->{borrowernumber} = $patron->borrowernumber;
        $backend_result->{borrowernumber} = $params->{other}->{borrowernumber};

        SLNP::Exception::MissingParameter->throw( param => 'title' )
            unless $params->{other}->{attributes}->{title};

        SLNP::Exception::MissingParameter->throw( param => 'medium' )
            unless $params->{other}->{medium};

        my $library_id = $params->{other}->{branchcode};

        SLNP::Exception::MissingParameter->throw( param => 'branchcode' )
            unless $library_id;

        SLNP::Exception::BadConfig->throw( param => 'default_ill_branch', value => $library_id )
            unless Koha::Libraries->find($library_id);

        my $biblio_id = $self->add_biblio( $params->{other} );
        my $item_id   = $self->add_item(
            {
                biblio_id  => $biblio_id,
                medium     => $params->{other}->{medium},
                library_id => $library_id,
                callnumber => $params->{other}->{attributes}->{shelfmark},
                notes      => undef,
                orderid    => $params->{other}->{orderid},                   # zflorderid
            }
        )->id;

        my $now = dt_from_string();
        my $fee = $self->charge_ill_fee( { patron => $patron, item_id => $item_id } );

        $params->{request}->set(
            {
                borrowernumber => $patron->borrowernumber,
                biblio_id      => $biblio_id,
                branchcode     => $library_id,
                status         => 'REQ',
                placed         => $now,
                updated        => $now,
                medium         => $params->{other}->{medium},
                orderid        => $params->{other}->{orderid},
                backend        => $self->name,
                price_paid     => "$fee",                                    # FIXME: varchar => formatting?
                notesstaff     => $params->{other}->{attributes}->{notes},
            }
        )->store;

        # populate table illrequestattributes
        $params->{other}->{attributes}->{item_id} = $item_id;
        while ( my ( $type, $value ) = each %{ $params->{other}->{attributes} } ) {

            try {
                Koha::ILL::Request::Attribute->new(
                    {
                        illrequest_id => $params->{request}->illrequest_id,
                        type          => $type,
                        value         => $value,
                    }
                )->store;
            };
        }

        $backend_result->{stage} = "commit";
        $backend_result->{value} = $params;
    }

    # Invalid stage, return error.
    else {
        $backend_result->{stage}  = $params->{stage};
        $backend_result->{error}  = 1;
        $backend_result->{status} = 'unknown_stage';
    }

    return $backend_result;
}

=head3 receive

    $backend->receive;

Handle receiving the request. It should involve the following I<stage>:

=over

=item B<no stage> initial stage, for rendering the form (a.k.a. I<init>).

=item B<commit> process the receiving parameters.

=back

=cut

sub receive {
    my ( $self, $params ) = @_;

    my $request = $params->{request};
    my $method  = $params->{other}->{method};
    my $stage   = $params->{other}->{stage};

    my $item = $self->get_item_from_request( { request => $request } );

    my $template_params = {};

    my $backend_result = {
        backend       => $self->name,
        method        => "receive",
        stage         => $stage,             # default for testing the template
        error         => 0,
        status        => "",
        message       => "",
        value         => $template_params,
        next          => "illview",
        illrequest_id => $request->id,
    };

    $backend_result->{strings} = $params->{request}->_backend->{strings}->{staff_receive};

    if ( !defined $stage ) {    # init
        $template_params->{medium} = $request->medium;

        my $partner_category_code = $self->{configuration}->{partner_category_code} // 'IL';
        $template_params->{mandatory_lending_library} = !defined $self->{configuration}->{mandatory_lending_library}
            ? 1                 # defaults to true
            : ( $self->{configuration}->{mandatory_lending_library} eq 'false' ) ? 0 : 1;

        my $lending_libraries = Koha::Patrons->search(
            { categorycode => $partner_category_code },
            { order_by     => [ 'surname', 'othernames' ] }
        );

        $self->{logger}->error("No patrons defined as lending libraries (categorycode=$partner_category_code)")
            unless $lending_libraries->count > 0;

        # search in attributes for lending_library
        # it is usually given as ISIL like 'DE-123' or like Sigel '714'
        my $selected_lending_library_isil = $request->extended_attributes->search({ type => 'sigel_lending_library' })->next;

        if ($selected_lending_library_isil) {

            # if ISIL/Sigel is wrapped <...>
            my $search_prefix =
              $self->{configuration}->{lending_library}->{search_prefix} // "";
            my $search_suffix =
              $self->{configuration}->{lending_library}->{search_suffix} // "";

            # patron db column in which the ISIL/Sigel is saved
            my $ill_library_id_column =
              $self->{configuration}->{lending_library}->{ill_library_id}
              // "othernames";

            if (
                grep( /^$ill_library_id_column$/,
                    ( 'surname', 'firstname', 'middle_name', 'othernames' ) )
              )
            {
                my $patron_query = "%". $search_prefix. $selected_lending_library_isil->value. $search_suffix . "%";

                my $selected_lending_library = Koha::Patrons->search( { $ill_library_id_column => { "like" => $patron_query }, categorycode => $partner_category_code })->single;

                if ($selected_lending_library) {
                    $template_params->{selected_lending_library_id} =
                      $selected_lending_library->borrowernumber;
                }
            }

        }


        # callnumber
        my $callnumber =
          $request->extended_attributes->search( { type => 'shelfmark' } )
          ->next;
        if ($callnumber) {
            $template_params->{callnumber} = $callnumber->value;
        }
        

        $template_params->{received_on_date}  = dt_from_string;
        $template_params->{lending_libraries} = $lending_libraries;
        $template_params->{item}              = $item;
        $template_params->{patron}            = $request->patron;

        # FIXME: Check in newer Koha how booleans are dealth with in YAML
        $template_params->{charge_extra_fee_by_default} = $self->{configuration}->{charge_extra_fee_by_default};

        my $patron_preferences = C4::Members::Messaging::GetMessagingPreferences(
            {
                borrowernumber => $template_params->{patron}->borrowernumber,
                message_name   => 'Ill_ready',
            }
        );

        if ( exists $patron_preferences->{transports}->{email} ) {
            $template_params->{notify} = 1;
        }

        $template_params->{opac_note}  = $request->notesopac;
        $template_params->{staff_note} = $request->notesstaff;

        $template_params->{item_types} = [
            { value => $self->get_item_type('copy'), selected => ( $request->medium eq 'copy' ) ? 1 : 0 },
            { value => $self->get_item_type('loan'), selected => ( $request->medium eq 'loan' ) ? 1 : 0 },
        ];

        $backend_result->{stage} = 'init';
    } elsif ( $stage eq 'commit' ) {

        # process the receiving parameters

        try {
            Koha::Database->new->schema->txn_do(
                sub {

                    my $request_type = $params->{other}->{type} // 'loan';

                    my $new_attributes = {};

                    $new_attributes->{type} = $request_type eq 'loan' ? 'Leihe' : 'Kopie';

                    $new_attributes->{received_on_date} = $params->{other}->{received_on_date}
                        if $params->{other}->{received_on_date};

                    $new_attributes->{due_date} = $params->{other}->{due_date}
                        if $params->{other}->{due_date};

                    $new_attributes->{lending_library} = $params->{other}->{lending_library}
                        if $params->{other}->{lending_library};

                    $request->cost( $params->{other}->{request_charges} );

                    $new_attributes->{request_charges} = $params->{other}->{request_charges}
                        if $params->{other}->{request_charges};

                    if (    $params->{other}->{charge_extra_fee}
                        and $params->{other}->{request_charges}
                        and $params->{other}->{request_charges} > 0 )
                    {
                        my $debit = $request->patron->account->add_debit(
                            {
                                amount    => $params->{other}->{request_charges},
                                item_id   => $item->id,
                                interface => 'intranet',
                                type      => $self->{configuration}->{extra_fee_debit_type} // 'ILL',
                            }
                        );

                        $new_attributes->{extra_fee_debit_id} = $debit->id;
                    }

                    $new_attributes->{circulation_notes} = $params->{other}->{circulation_notes}
                        if $params->{other}->{circulation_notes};

                    # place a hold on behalf of the patron
                    # FIXME: Should call CanItemBeReserved first?
                    my $biblio  = $request->biblio;
                    my $hold_id = C4::Reserves::AddReserve(
                        {
                            branchcode       => $request->branchcode,
                            borrowernumber   => $request->borrowernumber,
                            biblionumber     => $request->biblio_id,
                            priority         => 1,
                            reservation_date => undef,
                            expiration_date  => undef,
                            notes            => $self->{configuration}->{default_hold_note} // 'Placed by ILL',
                            title            => $biblio->title,
                            itemnumber       => $item->id,
                            found            => undef,
                            itemtype         => undef
                        }
                    );

                    $new_attributes->{hold_id} = $hold_id;

                    $self->add_or_update_attributes(
                        {
                            request    => $request,
                            attributes => $new_attributes,
                        }
                    );

                    # item information
                    my $item_type = $self->{configuration}->{item_types}->{$request_type};
                    $item->set(
                        {
                            itype               => $item_type,
                            restricted          => $params->{other}->{item_usage_restrictions},
                            itemcallnumber      => $params->{other}->{item_callnumber},
                            damaged             => $params->{other}->{item_damaged},
                            itemnotes_nonpublic => $params->{other}->{item_internal_note},
                            materials           => $params->{other}->{item_number_of_parts},
                        }
                    )->store;

                    $request->set(
                        {
                            due_date   => $params->{other}->{due_date},
                            medium     => $request_type,
                            notesopac  => $params->{other}->{opac_note},
                            notesstaff => $params->{other}->{staff_note},
                        }
                    )->store;

                    $request->status('RECVD');

                    $backend_result->{stage} = 'commit';
                }
            );
        } catch {
            warn "$_";
            if ( blessed($_) and $_->isa('Koha::Exceptions::Account::UnrecognisedType') ) {
                $backend_result->{status} = 'invalid_debit_type';
            } else {
                $backend_result->{status} = 'unknown';
            }

            $backend_result->{error} = 1;
            $backend_result->{stage} = 'commit';
        };
    } else {
        $backend_result->{stage} = $stage;
    }

    return $backend_result;
}

=head3 update

    $backend->update;

Handle updating the request.

=cut

sub update {
    my ( $self, $params ) = @_;

    my $request = $params->{request};
    my $method  = $params->{other}->{method};
    my $stage   = $params->{other}->{stage};

    my $item = $self->get_item_from_request( { request => $request } );

    my $template_params = {};

    my $backend_result = {
        backend       => $self->name,
        method        => "update",
        stage         => $stage,             # default for testing the template
        error         => 0,
        status        => "",
        message       => "",
        value         => $template_params,
        next          => "illview",
        illrequest_id => $request->id,
    };

    $backend_result->{strings} = $params->{request}->_backend->{strings}->{staff_update};

    if ( $stage and $stage eq 'commit' ) {

        # process the receiving parameters

        try {
            Koha::Database->new->schema->txn_do(
                sub {

                    my $request_type = $params->{other}->{type} // 'loan';

                    my $new_attributes = {};

                    $new_attributes->{type} = $request_type eq 'loan' ? 'Leihe' : 'Kopie';

                    $new_attributes->{received_on_date} = $params->{other}->{received_on_date}
                        if $params->{other}->{received_on_date};

                    $new_attributes->{due_date} = $params->{other}->{due_date}
                        if $params->{other}->{due_date};

                    if ( $params->{other}->{set_extra_fee} ) {

                        $request->cost( $params->{other}->{request_charges} );

                        $new_attributes->{request_charges} = $params->{other}->{request_charges}
                            if $params->{other}->{request_charges};

                        if (    $params->{other}->{charge_extra_fee}
                            and $params->{other}->{request_charges}
                            and $params->{other}->{request_charges} > 0 )
                        {
                            my $debit = $request->patron->account->add_debit(
                                {
                                    amount    => $params->{other}->{request_charges},
                                    item_id   => $item->id,
                                    interface => 'intranet',
                                    type      => $self->{configuration}->{extra_fee_debit_type} // 'ILL',
                                }
                            );

                            $new_attributes->{extra_fee_debit_id} = $debit->id;
                        }
                    }

                    $new_attributes->{lending_library} = $params->{other}->{lending_library};

                    $new_attributes->{circulation_notes} = $params->{other}->{circulation_notes}
                        if $params->{other}->{circulation_notes};

                    $self->add_or_update_attributes(
                        {
                            request    => $request,
                            attributes => $new_attributes,
                        }
                    );

                    # item information
                    $item->itype( $params->{other}->{item_type} )
                        if $params->{other}->{item_type};

                    $item->restricted( $params->{other}->{item_usage_restrictions} )
                        if defined $params->{other}->{item_usage_restrictions};

                    $item->itemcallnumber( $params->{other}->{item_callnumber} )
                        if $params->{other}->{item_callnumber};

                    $item->damaged( $params->{other}->{item_damaged} )
                        if $params->{other}->{item_damaged};

                    $item->itemnotes_nonpublic( $params->{other}->{item_internal_note} )
                        if $params->{other}->{item_internal_note};

                    $item->materials( $params->{other}->{item_number_of_parts} )
                        if $params->{other}->{item_number_of_parts};

                    $item->store;

                    if ( $params->{other}->{notify_patron} eq 'on' ) {
                        my $letter =
                            $request->get_notice( { notice_code => 'ILL_PICKUP_READY', transport => 'email' } );

                        my $result = C4::Letters::EnqueueLetter(
                            {
                                letter                 => $letter,
                                borrowernumber         => $request->borrowernumber,
                                message_transport_type => 'email',
                            }
                        );
                    }

                    # item information
                    my $item_type = $self->{configuration}->{item_types}->{$request_type};
                    $item->set(
                        {
                            itype               => $item_type,
                            restricted          => $params->{other}->{item_usage_restrictions},
                            itemcallnumber      => $params->{other}->{item_callnumber},
                            damaged             => $params->{other}->{item_damaged},
                            itemnotes_nonpublic => $params->{other}->{item_internal_note},
                            materials           => $params->{other}->{item_number_of_parts},
                        }
                    )->store;

                    $request->set(
                        {
                            due_date   => $params->{other}->{due_date},
                            medium     => $request_type,
                            notesopac  => $params->{other}->{opac_note},
                            notesstaff => $params->{other}->{staff_note},
                        }
                    )->store;

                    $backend_result->{stage} = 'commit';
                }
            );
        } catch {
            warn "$_";
            $backend_result->{error}   = 1;
            $backend_result->{message} = "$_";
            $backend_result->{stage}   = undef;
        };
    } else {    # init or error

        $template_params->{medium} = $request->medium;

        my $partner_category_code = $self->{configuration}->{partner_category_code} // 'IL';
        $template_params->{mandatory_lending_library} = !defined $self->{configuration}->{mandatory_lending_library}
            ? 1    # defaults to true
            : ( $self->{configuration}->{mandatory_lending_library} eq 'false' ) ? 0 : 1;

        my $lending_libraries = Koha::Patrons->search(
            { categorycode => $partner_category_code },
            { order_by     => [ 'surname', 'othernames' ] }
        );

        $template_params->{lending_libraries} = $lending_libraries;
        my $selected_lending_library = $request->extended_attributes->search( { type => 'lending_library' } )->next;
        $template_params->{selected_lending_library_id} = $selected_lending_library->value
            if $selected_lending_library;

        my $request_charges = $request->extended_attributes->search( { type => 'request_charges' } )->next;
        $template_params->{request_charges} = $request_charges->value
            if $request_charges;

        my $extra_fee_debit_id = $request->extended_attributes->search( { type => 'extra_fee_debit_id' } )->next;

        if ( $request_charges and $extra_fee_debit_id ) {
            $template_params->{disable_extra_fee} = 1;
        }

        my $circulation_notes = $request->extended_attributes->search( { type => 'circulation_notes' } )->next;
        $template_params->{circulation_notes} = $circulation_notes->value
            if $circulation_notes;

        my $received_on_date = $request->extended_attributes->search( { type => 'received_on_date' } )->next;
        $template_params->{received_on_date} = $received_on_date->value
            if $received_on_date;

        my $due_date = $request->extended_attributes->search( { type => 'due_date' } )->next;
        $template_params->{due_date} = $due_date->value
            if $due_date;

        $template_params->{item}   = $item;
        $template_params->{patron} = $request->patron;

        $template_params->{opac_note}  = $request->notesopac;
        $template_params->{staff_note} = $request->notesstaff;

        $template_params->{item_types} = [
            { value => $self->get_item_type('copy'), selected => ( $request->medium eq 'copy' ) ? 1 : 0 },
            { value => $self->get_item_type('loan'), selected => ( $request->medium eq 'loan' ) ? 1 : 0 },
        ];

        $backend_result->{stage} = 'init';
    }

    return $backend_result;
}

=head3 cancel_unavailable

    $request->cancel_unavailable;

=cut

sub cancel_unavailable {
    my ( $self, $params ) = @_;

    my $stage           = $params->{other}->{stage};
    my $template_params = {};

    my $backend_result = {
        backend => $self->name,
        method  => "cancel_unavailable",
        stage   => $stage,                 # default for testing the template
        error   => 0,
        status  => "",
        message => "",
        value   => $template_params,
        next    => "illview",
    };

    $backend_result->{strings} = $params->{request}->_backend->{strings}->{staff_cancel_unavailable};

    my $request = $params->{request};

    $backend_result->{illrequest_id}  = $request->illrequest_id;
    $template_params->{other}->{type} = $request->medium;
    $template_params->{request}       = $request;
    $template_params->{patron}        = $request->patron;

    if ( !$stage ) {

        my $patron_preferences = C4::Members::Messaging::GetMessagingPreferences(
            {
                borrowernumber => $request->borrowernumber,
                message_name   => 'Ill_unavailable',
            }
        );

        if ( exists $patron_preferences->{transports}->{email} ) {
            $template_params->{notify} = 1;
        }

        $backend_result->{stage} = "init";

    } elsif ( $stage eq 'commit' ) {

        try {
            Koha::Database->new->schema->txn_do(
                sub {
                    $self->biblio_cleanup($request);

                    $self->add_or_update_attributes(
                        {
                            request    => $request,
                            attributes => {
                                cancellation_reason         => 'unavailable',
                                cancellation_patron_message => $params->{other}->{cancellation_patron_message},
                                cancellation_patron_reason  => $params->{other}->{cancellation_patron_reason},
                            }
                        }
                    );

                    # mark as complete
                    $request->set(
                        {
                            completed => \'NOW()',
                        }
                    );

                    $request->status('COMP');

                    # send message
                    if ( $params->{other}->{notify_patron} eq 'on' ) {
                        my $letter =
                            $request->get_notice( { notice_code => 'ILL_REQUEST_UNAVAIL', transport => 'email' } );
                        my $result = C4::Letters::EnqueueLetter(
                            {
                                letter                 => $letter,
                                borrowernumber         => $request->borrowernumber,
                                message_transport_type => 'email',
                            }
                        );
                    }
                }
            )
        } catch {
            warn "$_";
            $backend_result->{error}   = 1;
            $backend_result->{message} = "$_";
            $backend_result->{stage}   = undef;
        };

    } else {

        # in case of faulty or testing stage, we just return the standard $backend_result with original stage
        $backend_result->{stage} = $stage;
    }

    return $backend_result;
}

=head3 mark_lost

    $request->mark_lost;

=cut

sub mark_lost {
    my ( $self, $params ) = @_;

    my $stage           = $params->{other}->{stage};
    my $template_params = {};

    my $backend_result = {
        backend => $self->name,
        method  => "mark_lost",
        stage   => $stage,             # default for testing the template
        error   => 0,
        status  => "",
        message => "",
        value   => $template_params,
        next    => "illview",
    };

    $backend_result->{strings} = $params->{request}->_backend->{strings}->{staff_mark_lost};

    my $request = $params->{request};
    my $item    = $self->get_item_from_request( { request => $request } );

    $backend_result->{illrequest_id} = $request->illrequest_id;
    $template_params->{request}      = $request;
    $template_params->{patron}       = $request->patron;
    $template_params->{item}         = $item;

    my $selected_lending_library = $request->extended_attributes->search( { type => 'lending_library' } )->next;

    my $due_date = $request->extended_attributes->search( { type => 'due_date' } )->next;
    $template_params->{due_date} = dt_from_string( $due_date->value )
        if $due_date;

    if ( !$stage ) {

        if ( !$item->itemlost ) {
            $template_params->{item_not_lost} = 1;
        }

        my $partner_category_code = $self->{configuration}->{partner_category_code} // 'IL';
        $template_params->{mandatory_lending_library} = !defined $self->{configuration}->{mandatory_lending_library}
            ? 1    # defaults to true
            : ( $self->{configuration}->{mandatory_lending_library} eq 'false' ) ? 0 : 1;

        my $lending_libraries = Koha::Patrons->search(
            { categorycode => $partner_category_code },
            { order_by     => [ 'surname', 'othernames' ] }
        );

        $template_params->{lending_libraries} = $lending_libraries;
        my $selected_lending_library = $request->extended_attributes->search( { type => 'lending_library' } )->next;

        if ($selected_lending_library) {

            $template_params->{selected_lending_library_id} = $selected_lending_library->value
                if $selected_lending_library;
        }

        $backend_result->{stage} = "init";

    } elsif ( $stage eq 'commit' ) {

        try {
            Koha::Database->new->schema->txn_do(
                sub {

                    $self->add_or_update_attributes(
                        {
                            request    => $request,
                            attributes => {
                                lending_library     => $params->{other}->{lending_library},
                                cancellation_reason => 'lost'
                            }
                        }
                    );

                    $request->set( { completed => \'NOW()', } );
                    $request->status('SLNP_LOST_COMP');

                    # send message
                    if (    $params->{other}->{notify_lending_library} eq 'on'
                        and $params->{other}->{lending_library} )
                    {
                        my $letter =
                            $request->get_notice( { notice_code => 'ILL_PARTNER_LOST', transport => 'email' } );
                        my $result = C4::Letters::EnqueueLetter(
                            {
                                letter                 => $letter,
                                borrowernumber         => $params->{other}->{lending_library},
                                message_transport_type => 'email',
                            }
                        );
                    }
                }
            )
        } catch {
            warn "$_";
            $backend_result->{error}   = 1;
            $backend_result->{message} = "$_";
            $backend_result->{stage}   = undef;
        };

    } else {

        # in case of faulty or testing stage, we just return the standard $backend_result with original stage
        $backend_result->{stage} = $stage;
    }

    return $backend_result;
}

=head3 cancel

    $request->cancel;

Cancel the request and perform the required cleanup

=cut

sub cancel {
    my ( $self, $params ) = @_;

    my $backend_result = {
        error   => 0,
        status  => '',
        message => '',
        method  => 'cancel',
        stage   => 'commit',
        next    => 'illlist',
        value   => '',
    };

    my $request = $params->{request};

    try {
        Koha::Database->new->schema->txn_do(
            sub {
                $self->biblio_cleanup($request);

                $self->add_or_update_attributes(
                    {
                        attributes => { cancellation_reason => 'cancelled' },
                        request    => $request,
                    }
                );

                # mark as complete
                $request->set(
                    {
                        completed => \'NOW()',
                    }
                )->store;

                $request->status('COMP');
            }
        )
    } catch {
        warn "$_";
        $backend_result->{stage}   = 'init';
        $backend_result->{message} = "$_";
    };

    return $backend_result;
}

=head3 slnp_mark_completed

    $request->slnp_mark_completed;

FIXME: I didn't find a way for I<mark_completed> to override the one from
Koha::ILL::Request. So...

=cut

sub slnp_mark_completed {
    my ( $self, $params ) = @_;

    my $backend_result = {
        error   => 0,
        status  => '',
        message => '',
        method  => 'slnp_mark_completed',
        stage   => 'commit',
        next    => 'illview',
        value   => '',
    };

    my $request = $params->{request};

    try {
        Koha::Database->new->schema->txn_do(
            sub {
                $self->biblio_cleanup($request);

                # mark as complete
                $request->set(
                    {
                        completed => \'NOW()',
                    }
                )->store;

                $request->status('COMP');
            }
        )
    } catch {
        warn "$_";
        $backend_result->{stage}   = 'init';
        $backend_result->{message} = "$_";
    };

    return $backend_result;
}

=head3 return_to_library

    $request->return_to_library;

=cut

sub return_to_library {
    my ( $self, $params ) = @_;

    my $request = $params->{request};
    my $method  = $params->{other}->{method};
    my $stage   = $params->{other}->{stage};

    my $template_params = {};

    my $backend_result = {
        backend       => $self->name,
        method        => 'return_to_library',
        stage         => $stage,                # default for testing the template
        error         => 0,
        status        => "",
        message       => "",
        value         => $template_params,
        next          => "illview",
        illrequest_id => $request->id,
    };

    $backend_result->{strings} = $params->{request}->_backend->{strings}->{staff_return_to_library};

    if ( $stage && $stage eq 'commit' ) {

        # process the incoming parameters

        try {
            Koha::Database->new->schema->txn_do(
                sub {

                    $self->add_or_update_attributes(
                        {
                            request    => $request,
                            attributes => {
                                lending_library => $params->{other}->{lending_library},
                            }
                        }
                    );

                    $request->set( { notesstaff => $params->{other}->{staff_note}, } )->store;
                    $request->status('SENT_BACK');
                }
            );

            $backend_result->{stage} = 'commit';
        } catch {
            warn "$_";
            $backend_result->{stage}   = 'init';
            $backend_result->{message} = "$_";
        };
    } else {

        # init, show information

        my $partner_category_code = $self->{configuration}->{partner_category_code} // 'IL';
        $template_params->{mandatory_lending_library} = !defined $self->{configuration}->{mandatory_lending_library}
            ? 1    # defaults to true
            : ( $self->{configuration}->{mandatory_lending_library} eq 'false' ) ? 0 : 1;

        my $lending_libraries = Koha::Patrons->search(
            { categorycode => $partner_category_code },
            { order_by     => [ 'surname', 'othernames' ] }
        );

        $template_params->{lending_libraries} = $lending_libraries;
        my $selected_lending_library = $request->extended_attributes->search( { type => 'lending_library' } )->next;
        $template_params->{selected_lending_library_id} = $selected_lending_library->value
            if $selected_lending_library;

        $template_params->{patron}     = $request->patron;
        $template_params->{staff_note} = $request->notesstaff;
    }

    return $backend_result;
}

=head2 Internal methods

=head3 add_biblio

    my $biblionumber = $slnp_backend->add_biblio($params->{other});

Create a basic biblio record for the passed SLNP API request

=cut

sub add_biblio {
    my ( $self, $other ) = @_;

    return try {

        # We're going to try and populate author, title, etc.
        my $author = $other->{attributes}->{author};
        my $title  = $other->{attributes}->{title};
        my $isbn   = $other->{attributes}->{isbn};
        my $issn   = $other->{attributes}->{issn};

        # article fields
        my $article_author = $other->{attributes}->{article_author};
        my $article_title  = $other->{attributes}->{article_title};
        my $issue          = $other->{attributes}->{issue};
        my $pages          = $other->{attributes}->{pages};
        my $volume         = $other->{attributes}->{volume};
        my $year           = $other->{attributes}->{year};

        my $configuration = $self->{configuration};

        # Create the MARC::Record object and populate it
        my $record = MARC::Record->new();
        $record->MARC::Record::encoding('UTF-8');

        if ($article_title) {    # it's an article! do the right things!

            my @subfields;

            if ( defined $article_title && length $article_title > 0 ) {

                my $prefix = $configuration->{title_prefix} // '';
                my $suffix = $configuration->{title_suffix} // '';

                push @subfields, 'a' => $prefix . $article_title . $suffix;
            }

            if ( defined $article_author && length $article_author > 0 ) {

                push @subfields, 'c' => $article_author;
            }

            $record->insert_fields_ordered( MARC::Field->new( '245', '0', ' ', @subfields ) )
                if scalar @subfields;

            # build 773
            my $field_773_g;

            $field_773_g = $volume
                if defined $volume and $volume != 0;

            $field_773_g = join( ' ', $field_773_g, "($year)" )
                if defined $year;

            $field_773_g = join( ' ', $field_773_g, $issue )
                if defined $issue and $issue != 0;

            $field_773_g = join( ' ', $field_773_g, $pages )
                if defined $pages and $pages != 0;

            @subfields = ();

            push @subfields, 'g' => $field_773_g
                if $field_773_g;

            push @subfields, 't' => $title
                if $title;

            $record->insert_fields_ordered( MARC::Field->new( '773', '0', '0', @subfields ) )
                if scalar @subfields;

        } else {

            my @subfields;

            if ( defined $title && length $title > 0 ) {

                my $prefix = $configuration->{title_prefix} // '';
                my $suffix = $configuration->{title_suffix} // '';

                push @subfields, 'a' => $prefix . $title . $suffix;
            }
            if ( defined $author && length $author > 0 ) {

                push @subfields, 'c' => $author;
            }

            $record->insert_fields_ordered( MARC::Field->new( '245', '0', '0', @subfields ) )
                if scalar @subfields;
        }

        $record->insert_fields_ordered( MARC::Field->new( '020', ' ', ' ', 'a' => $isbn ) )
            if defined $isbn && length $isbn > 0;

        $record->insert_fields_ordered( MARC::Field->new( '022', ' ', ' ', 'a' => $issn ) )
            if defined $issn && length $issn > 0;

        $record->insert_fields_ordered( MARC::Field->new( '100', '1', ' ', 'a' => $author ) )
            if $author;

        # set opac display suppression flag of the record
        $record->insert_fields_ordered( MARC::Field->new( '942', '', '', n => '1' ) );

        my $biblionumber = C4::Biblio::AddBiblio( $record, $self->{framework} );

        return $biblionumber;
    } catch {
        SLNP::Exception->throw("error_creating_biblio");
    };
}

=head3 add_item

    my $item = $slnp_backend->add_item(
        {
            biblio_id       => $biblio->id,
            medium          => 'Book' / 'Article',
            library_id      => $library_id,
            callnumber      => $callnumber,
            notes           => $item_notes,
            notes_nonpublic => $item_notes_nonpublic,
        }
    );

Create a I<Koha::Item> object from the ill request data.

=cut

sub add_item {
    my ( $self, $params ) = @_;

    my @mandatory = ( 'biblio_id', 'medium', 'library_id', 'orderid' );
    for my $param (@mandatory) {
        unless ( defined( $params->{$param} ) ) {
            SLNP::Exception::MissingParameter->throw( param => $param );
        }
    }

    my $biblio  = Koha::Biblios->find( $params->{biblio_id} );
    my $request = $params->{request};

    unless ($biblio) {
        SLNP::Exception::UnknownBiblioId->throw( biblio_id => $params->{biblio_id} );
    }

    my $item_type = $self->get_item_type( $params->{medium} );

    # Barcode needs to be prefixed
    my $barcode = $self->{configuration}->{barcode_prefix} . $params->{orderid};

    return Koha::Item->new(
        {
            homebranch          => $params->{library_id},
            barcode             => $barcode,
            notforloan          => undef,
            itemcallnumber      => undef,
            itemnotes           => $params->{notes},
            itemnotes_nonpublic => $params->{notes_nonpublic},
            holdingbranch       => $params->{library_id},
            itype               => $item_type,
            biblionumber        => $biblio->biblionumber,
            biblioitemnumber    => $biblio->biblioitem->biblioitemnumber,
            stocknumber         => undef,
        }
    )->store;
}

=head3 get_fee

    my $fee = $self->get_fee({ patron => $patron });

Given a I<Koha::Patron> object, it returns the configured request fee.

=cut

sub get_fee {
    my ( $self, $args ) = @_;

    my $patron = $args->{patron};
    SLNP::Exception::BadParameter->throw( param => 'patron', value => $patron )
        unless $patron and ref($patron) eq 'Koha::Patron';

    my $configuration = $self->{configuration};

    my $default_fee = ( exists $configuration->{default_fee} )
        ? $configuration->{default_fee} // 0    # explicit undef means 'no charge'
        : 0;

    my $fee =
        ( exists $configuration->{category_fee} and exists $configuration->{category_fee}->{ $patron->categorycode } )
        ? $configuration->{category_fee}->{ $patron->categorycode } // 0    # explicit undef means 'no charge'
        : $default_fee;

    return $fee;
}

=head3 get_item_type

    my $item_type = $self->get_item_type( $medium );

Given the calculated I<illrequest.medium> value passed to the I<create> method,
this helper will return the right item type for the request, given the local
settings.

=cut

sub get_item_type {
    my ( $self, $medium ) = @_;

    SLNP::Exception::BadParameter->throw( param => 'medium', value => $medium )
        unless $medium eq 'copy' or $medium eq 'loan';

    my $item_type;
    my $item_types = $self->{configuration}->{item_types};

    if ($item_types) {

        # Use the configuration if possible
        $item_type =
            ( $medium eq 'copy' )
            ? $self->{configuration}->{item_types}->{copy} // 'CR'
            : $self->{configuration}->{item_types}->{loan} // 'BK';
    } else {

        # No configuration, default values
        $item_type = ( $medium eq 'copy' ) ? 'CR' : 'BK';
    }

    $self->{logger}->error("Configured item type for '$medium' is not valid: $item_type")
        unless Koha::ItemTypes->find($item_type);

    return $item_type;
}

=head3 charge_ill_fee

    $self->charge_ill_fee({ patron => $patron });

Given a I<Koha::Patron> object, it charges the corresponding fee.

=cut

sub charge_ill_fee {
    my ( $self, $args ) = @_;

    my $patron = $args->{patron};
    SLNP::Exception::BadParameter->throw( param => 'patron', value => $patron )
        unless $patron and ref($patron) eq 'Koha::Patron';

    my $fee        = $self->get_fee( { patron => $patron } );
    my $debit_type = $self->{configuration}->{fee_debit_type} // 'ILL';

    if ( $fee > 0 ) {
        try {
            $patron->account->add_debit(
                {
                    amount    => $fee,
                    interface => 'intranet',
                    type      => $debit_type,
                    ( $args->{item_id} ? ( item_id => $args->{item_id} ) : () )
                }
            );
        } catch {
            if ( $_->isa('Koha::Exceptions::Account::UnrecognisedType') ) {
                SLNP::Exception::BadConfig->throw(
                    param => 'fee_debit_type',
                    value => $debit_type,
                );

                $_->rethrow;
            }

        };
    }

    return $fee;
}

=head3 get_item_from_request

    $self->get_item_from_request({ request => $request });

Given a I<Koha::ILL::Request> object, retrieve the linked I<Koha::Item> object.

=cut

sub get_item_from_request {
    my ( $self, $args ) = @_;

    my $request = $args->{request};
    SLNP::Exception::BadParameter->throw( param => 'patron', value => $request )
        unless $request and ref($request) eq 'Koha::ILL::Request';

    my $item_id_attributes = $request->extended_attributes->search( { type => 'item_id' } );

    SLNP::Exception::UnknownItemId->throw("Request not linked to an item when it should")
        unless $item_id_attributes->count > 0;

    my $item_id = $item_id_attributes->next->value;
    my $item    = Koha::Items->find($item_id);

    SLNP::Exception::UnknownItemId->throw("Request not linked to an item when it should")
        unless $item;

    return $item;
}

=head3 biblio_cleanup

    $request->biblio_cleanup;

Removes the associated biblio and item.

=cut

sub biblio_cleanup {
    my ( $self, $request ) = @_;

    try {
        Koha::Database->new->schema->txn_do(
            sub {
                SLNP::Exception::MissingParameter->throw( param => 'biblio_id' )
                    unless $request->biblio_id;

                my $biblio = Koha::Biblios->find( $request->biblio_id );
                SLNP::Exception::UnknownBiblioId->throw( biblio_id => $request->biblio_id )
                    unless $biblio;

                my $holds = $biblio->holds;
                while ( my $hold = $holds->next ) {
                    $hold->cancel( { skip_holds_queue => 1 } );    # skip_holds_queue used in 22.05+
                }

                my $items = $biblio->items;
                while ( my $item = $items->next ) {
                    $item->safe_delete;
                }

                DelBiblio( $biblio->id );
            }
        );
    } catch {
        warn "$_ " . ref($_);
    };

    return $self;
}

=head3 add_or_update_attributes

    $request->add_or_update_attributes(
        {
            request    => $request,
            attributes => {
                $type_1 => $value_1,
                $type_2 => $value_2,
                ...
            },
        }
    );

Takes care of updating or adding attributes if they don't already exist.

=cut

sub add_or_update_attributes {
    my ( $self, $params ) = @_;

    my $request    = $params->{request};
    my $attributes = $params->{attributes};

    try {
        Koha::Database->new->schema->txn_do(
            sub {

                while ( my ( $type, $value ) = each %{$attributes} ) {

                    my $attr = $request->extended_attributes->find( { type => $type } );

                    if ($attr) {    # update
                        if ( $attr->value ne $value ) {
                            $attr->update( { value => $value, } );
                        }
                    } else {        # new
                        $attr = Koha::ILL::Request::Attribute->new(
                            {
                                illrequest_id => $request->id,
                                type          => $type,
                                value         => $value,
                            }
                        )->store;
                    }
                }
            }
        );
    } catch {
        $_->rethrow;
    };

    return $self;
}

1;
