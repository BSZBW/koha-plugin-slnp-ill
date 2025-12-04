[% USE Asset %]
[% USE AuthorisedValues %]
[% SET footerjs = 1 %]

[% IF whole.error %]
    [% IF whole.message %]
    <div class="dialog message">[% whole.strings.error | html %]: [%- whole.message | html -%].</div>
    [% ELSE %]
    <p>[% whole.strings.unknown_error | html %]</p>
    [% END %]
[% END %]

[% IF ( whole.stage == "init" ) %]
    <h2>[% whole.strings.title | html %] ([% request.orderid | html %])</h2>

    [% IF ! ( request.status == 'REQ' ) %]
        <p>[% whole.strings.wrong_status_text_1 | html %] ([% request.status | html %]) [% whole.strings.wrong_status_text_2 | html %].</p>
        <p>[% whole.strings.wrong_status_text_3 | html %].</p>

        <a class="cancel" href="/cgi-bin/koha/ill/ill-requests.pl?method=illview&amp;illrequest_id=[% request.illrequest_id | uri %]">[% whole.strings.cancel | html %]</a>

    [% ELSE %]

        <form id="SLNP_cancel_unavailable" name="SLNP_cancel_unavailable" method="POST" action=[% here | url %]>
            [% INCLUDE 'csrf-token.inc' %]
            <fieldset class="rows">
                <legend>[% whole.strings.cancellation | html %]</legend>
                <ol>
                    <li>
                        <label for="the_patron">[% whole.strings.requesting_patron | html %]:</label>
                        <div name="the_patron" id="the_patron">
                            <a target="_blank" href="/cgi-bin/koha/members/moremember.pl?borrowernumber=[% whole.value.patron.borrowernumber %]">
                            [% whole.value.patron.firstname | html %] [% whole.value.patron.surname | html %] ([% whole.value.patron.cardnumber | html %])</a>
                        </div>
                    </li>
                    <li>
                        <label for="notify_patron">[% whole.strings.notify | html %]:</label>
                    [% IF whole.value.notify %]
                        <input type="checkbox" id="notify_patron" name="notify_patron" checked />
                    [% ELSE %]
                        <input type="checkbox" id="notify_patron" name="notify_patron" />
                    [% END %]
                    </li>
                    <li>
                        <label for="cancellation_patron_reason">[% whole.strings.cancellation_patron_reason | html %]:</label>
                        [% PROCESS 'av-build-dropbox.inc' name="cancellation_patron_reason", category="ILL_CANCELLATION_REASON", empty=1 %]
                    </li>
                    <li>
                        <label for="patron_message">[% whole.strings.cancellation_patron_message | html %]:</label>
                        <textarea id="cancellation_patron_message" name="cancellation_patron_message" rows="4" cols="40"></textarea>
                    </li>
                </ol>

                <input name="illrequest_id" id="illrequest_id" value="[% whole.illrequest_id | html%]" type="hidden" />
                <input name="backend" id="backend" value="SLNP" type="hidden" />
                <input name="method" id="method" value="cancel_unavailable" type="hidden" />
                <input name="stage" id="stage" value="commit" type="hidden" />
                <input type="hidden" name="op" value="cud-cancel_unavailable" />
            </fieldset>

            <fieldset class="action">
                <button type="submit" class="btn btn-default approve">
                    <i class="fa fa-check"></i> [% whole.strings.cancel_request | html %]
                </button>

                <a class="cancel" id="cancelbutton" name="cancelbutton" href="/cgi-bin/koha/ill/ill-requests.pl?method=illview&amp;illrequest_id=[% request.illrequest_id | uri %]">[% whole.strings.cancel | html %]</a>
            </fieldset>
        </form>
    [% END %]

[% ELSE %]
    <p>[% whole.strings.unknown_stage | html %]: [% whole.stage %]</p>
[% END %]
