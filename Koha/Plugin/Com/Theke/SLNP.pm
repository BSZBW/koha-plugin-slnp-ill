package Koha::Plugin::Com::Theke::SLNP;

# Copyright 2021 Theke Solutions
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

use base qw(Koha::Plugins::Base);

use Encode qw(encode_utf8 decode_utf8);
use List::MoreUtils qw(any);
use Module::Metadata;
use Mojo::JSON qw(decode_json encode_json);
use Try::Tiny;
use YAML::XS;

use C4::Biblio qw(DelBiblio);
use C4::Circulation qw(AddReturn);
use C4::Languages;

use Koha::Account::DebitTypes;
use Koha::Illrequests;
use Koha::Items;
use Koha::Notice::Templates;

BEGIN {
    my $path = Module::Metadata->find_module_by_name(__PACKAGE__);
    $path =~ s!\.pm$!/lib!;
    unshift @INC, $path;
}

our $VERSION = "2.2.13";

our $metadata = {
    name            => 'SLNP ILL connector plugin for Koha',
    author          => 'Theke Solutions',
    date_authored   => '2018-09-10',
    date_updated    => "1980-06-18",
    minimum_version => '22.1100000',
    maximum_version => undef,
    version         => $VERSION,
    description     => 'SLNP ILL connector plugin for Koha'
};

=head1 Koha::Plugin::Com::Theke::SLNP

SLNP ILL connector plugin for Koha

=head2 Plugin methods

=head3 new

Constructor:

    my $plugin = Koha::Plugin::Com::Theke::SLNP->new;

=cut

sub new {
    my ( $class, $args ) = @_;

    $args->{'metadata'} = $metadata;
    $args->{'metadata'}->{'class'} = $class;

    my $self = $class->SUPER::new($args);

    return $self;
}

=head3 configure

Plugin configuration method

=cut

sub configure {
    my ( $self, $args ) = @_;

    my $template = $self->get_template({ file => 'configure.tt' });
    my $cgi = $self->{cgi};

    if ( scalar $cgi->param('save') ) {

        $self->store_data( { configuration => scalar $cgi->param('configuration'), } );
    }

    my $errors = $self->check_configuration;

    $template->param(
        errors        => $errors,
        configuration => $self->retrieve_data('configuration'),
        strings       => $self->get_strings->{configure},
    );

    $self->output_html( $template->output() );
}

=head3 configuration

Accessor for the de-serialized plugin configuration

=cut

sub configuration {
    my ($self) = @_;

    my $configuration;

    eval {
        $configuration = YAML::XS::Load(
            Encode::encode_utf8( $self->retrieve_data('configuration') ) );
    };

    warn "[SLNP]" . $@
      if $@;

    return $configuration;
}

=head3 api_routes

Method that returns the API routes to be merged into Koha's

=cut

sub api_routes {
    my ( $self, $args ) = @_;

    my $spec_str = $self->mbf_read('openapi.json');
    my $spec     = decode_json($spec_str);

    return $spec;
}

=head3 api_namespace

Method that returns the namespace for the plugin API to be put on

=cut

sub api_namespace {
    my ( $self ) = @_;

    return 'slnp';
}

=head3 intranet_js

Method that returns JS to be injected to the staff interface.

=cut

sub intranet_js {
    my ( $self ) = @_;

    unless ( $self->{_intranet_js} ) {
        my $js = decode_utf8($self->mbf_read('intranet.js'));
        $self->{_intranet_js} =  '<script>' . $js . '</script>';
    }

    return $self->{_intranet_js};
}

=head3 opac_js

Method that returns JS to be injected to the OPAC interface.

=cut

sub opac_js {
    my ( $self ) = @_;

    unless ( $self->{_opac_js} ) {
        my $js = decode_utf8($self->mbf_read('opac.js'));
        my $portal_url = $self->configuration->{portal_url} // 'https://your.portal.url';
        $js =~ s/\{\{portal_url\}\}/$portal_url/eg;
        $self->{_opac_js} =  '<script>' . $js . '</script>';
    }

    return $self->{_opac_js};
}

=head3 after_circ_action

After circulation hook.

=cut

sub after_circ_action {
    my ($self, $params) = @_;

    if ( $params->{action} eq 'checkout' ) {
        my $checkout  = $params->{payload}->{checkout};

        my $biblio_id = $checkout->item->biblionumber;
        my $patron_id = $checkout->borrowernumber;

        my $req = $self->get_recvd_ill_req({ biblio_id => $biblio_id, patron_id => $patron_id });

        if ( $req ) { # Yay

            $req->status('CHK');
            my $type = $req->illrequestattributes->search({ type => 'type' })->next;
            my $THE_type = ($type) ? $type->value : 'Leihe';

            unless ( $THE_type eq 'Leihe' ) {
                # This is Kopie
                try {
                    my $item = $checkout->item;
                    AddReturn( $item->barcode );
                    $req->status('SLNP_COMP');
                    # refetch item
                    $item->discard_changes;
                    my $not_for_loan_status = $self->configuration->{not_for_loan_after_auto_checkin} // 1;
                    $item->notforloan($not_for_loan_status)->store;
                }
                catch {
                    warn "Error attempting to return: $_";
                }
            }
        }
    }
}

=head3 after_item_action

After item actions

=cut

sub after_item_action {
    my ($self, $params) = @_;

    if (    $params->{action} eq 'modify' # we only care if the item has been updated
        and $params->{item}->itemlost ) { # and the item is lost

        my $item_id = $params->{item_id};

        my $attrs = Koha::Illrequestattributes->search(
            {   type  => 'item_id',
                value => $item_id,
            }
        );

        my $attrs_count = $attrs->count;

        if ( $attrs_count > 0 ) {

            warn "SLNP warning: More than one request for the item ($item_id)."
              if $attrs_count > 1;

            my $attr = $attrs->next;
            my $request = Koha::Illrequests->find( $attr->illrequest_id );

            if (    $request
                and (
                    $request->status eq 'RECVD'
                or $request->status eq 'CHK'
                or $request->status eq 'RET'
                ) ) {
                    $request->status( 'SLNP_LOST' );
                }
        }
    }

    return $self;
}

=head3 cronjob_nightly

Nightly cronjob hook that performs required cleanup on ILL requests that are marked
so. Right now only I<SLNP_COMP> status is considered for completion and cleanup.

=cut

sub cronjob_nightly {
    my ($self) = @_;

    # find the SLNP_COMPLETE ILL requests
    my $requests = Koha::Illrequests->search(
        {
            status => [ 'SENT_BACK', 'SLNP_COMP' ]
        }
    );

    while ( my $request = $requests->next ) {

        # mark as complete
        $request->set(
            {
                completed => \'NOW()',
            }
        )->store;

        $request->status('COMP');

        $request->_backend->biblio_cleanup($request);
    }

    return $self;
}

=head2 Internal methods

=head3 get_recvd_ill_req

    my $req = $self->get_recvd_ill_req({ biblio_id => $biblio_id, patron_id => $patron_id });

Returns the related I<Koha::Illrequest> object if found.

=cut

sub get_recvd_ill_req {
    my ( $self, $params ) = @_;

    my $biblio_id = $params->{biblio_id};
    my $patron_id = $params->{patron_id};

    my $reqs = Koha::Illrequests->search(
        {   biblio_id      => $biblio_id,
            borrowernumber => $patron_id,
            status         => 'RECVD'
        }
    );

    if ( $reqs->count > 1 ) {
        warn "slnp_plugin_warn: more than one RECVD ILL request for biblio_id ($biblio_id) and patron_id ($patron_id) <.<";
    }

    return unless $reqs->count > 0;

    my $req = $reqs->next;

    return $req;
}

=head3 get_strings

    my $strings = $self->get_strings;

Returns the translated strings.

=cut

sub get_strings {
    my ($self) = @_;

    my $lang = C4::Languages::getlanguage(CGI->new);
    my @lang_split = split /_|-/, $lang;
    my $plugin_dir = $self->bundle_path;

    my $strings;
    
    unless ( $lang eq 'en' ) {
        try {
            $strings = YAML::XS::LoadFile( "$plugin_dir/i18n/$lang" . ".yaml" );
        }
        catch {
            warn "Couldn't load '$lang' translation file.";
        };
    }

    unless ($strings) {
        $strings = YAML::XS::LoadFile( "$plugin_dir/i18n/en.yaml" );
    }

    return $strings;
}


=head3 check_configuration

    my $errors = $self->check_configuration;

Returns a reference to a list of errors found in configuration.

=cut

sub check_configuration {
    my ($self) = @_;

    my @errors;

    try {

        my $configuration = $self->configuration;

        if ( $configuration->{fee_debit_type} ) {
            push @errors, 'no_fee_debit_type'
              unless Koha::Account::DebitTypes->find( $configuration->{fee_debit_type} );
        } else {
            push @errors, 'fee_debit_type_not_set';
        }

        if ( $configuration->{extra_fee_debit_type} ) {
            push @errors, 'no_extra_fee_debit_type'
              unless Koha::Account::DebitTypes->find( $configuration->{extra_fee_debit_type} );
        } else {
            push @errors, 'extra_fee_debit_type_not_set';
        }

        eval {
            $configuration = YAML::XS::Load(
                Encode::encode_utf8( $self->retrieve_data('configuration') ) );
        };
        push @errors, "Error parsing YAML configuration ($@)"
          if $@;
    } catch {
        push @errors, "Error parsing YAML configuration ($_)";
    };

    push @errors, 'no_ILL_PARTNER_RET'
      unless Koha::Notice::Templates->search( { code => 'ILL_PARTNER_RET' } )->count;

    push @errors, 'no_ILL_RECEIVE_SLIP'
      unless Koha::Notice::Templates->search( { code => 'ILL_RECEIVE_SLIP' } )->count;

    push @errors, 'no_ILL_PARTNER_LOST'
      unless Koha::Notice::Templates->search( { code => 'ILL_PARTNER_LOST' } )->count;

    push @errors, 'ILLModule_disabled'
      unless C4::Context->preference('ILLModule');

    push @errors, 'CirculateILL_disabled'
      unless C4::Context->preference('CirculateILL');

    return \@errors;
}

1;
