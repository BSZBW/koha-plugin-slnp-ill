[% USE raw %]
[% USE Asset %]
[% SET footerjs = 1 %]

[% USE Koha %]
[% USE AuthorisedValues %]
[% USE ItemTypes %]
[% USE KohaDates %]
[% USE Price %]

[%# IF whole.error %]
  [% IF whole.message %]
    <p class="dialog alert">[% whole.strings.error | html %]: [% whole.message | html %]</p>
  [% END %]
[%# END %]

  <h2>[% whole.strings.return_to_library | html %] ([% request.orderid | html %])</h2>

  <form id="SLNP_return_to_library" name="SLNP_return_to_library" method="POST" action=[% here | url %]>
    [% INCLUDE 'csrf-token.inc' %]
    <fieldset class="rows">
      <legend>[% whole.strings.delivery | html %]</legend>
      <ol id="general-slnp_delivery-fields">
        <li>
        [% IF whole.value.mandatory_lending_library %]
            <label class="required" for="lending_library">[% whole.strings.lending_library | html %]:</label>
            <select name="lending_library" id="lending_library" required="required" class="select2" style="width: 45%">
        [% ELSE %]
            <label for="lending_library">[% whole.strings.lending_library | html %]:</label>
            <select name="lending_library" id="lending_library" class="select2" style="width: 45%">
        [% END %]
                <option value="">&nbsp;</option>
        [% FOREACH library IN whole.value.lending_libraries %]
            [% IF whole.value.selected_lending_library_id and whole.value.selected_lending_library_id == library.id %]
                <option value="[% library.borrowernumber | html %]" selected="selected">[% library.surname | html %][% IF library.othernames %] ([% library.othernames | html %])[% END %]</option>
            [% ELSE %]
                <option value="[% library.borrowernumber | html %]">[% library.surname | html %][% IF library.othernames %] ([% library.othernames | html %])[% END %]</option>
            [% END %]
        [% END %]
            </select>
        </li>
      </ol>
    </fieldset>

    <fieldset class="rows">
    <legend>[% whole.strings.request | html %]</legend>
      <ol>
        <li>
          <label for="staff_note">[% whole.strings.request_staff_note | html %]:</label>
          <textarea id="staff_note" name="staff_note" rows="4" cols="50">[% whole.value.staff_note | html %]</textarea>
        </li>
      </ol>
    </fieldset>

    <fieldset class="rows">
    <legend>[% whole.strings.patron | html %]</legend>
      <ol>
        <li>
          <label for="the_patron">[% whole.strings.patron_requester | html %]:</label>
          <div name="the_patron" id="the_patron">
            <a target="_blank" href="/cgi-bin/koha/members/moremember.pl?borrowernumber=[% whole.value.patron.borrowernumber | uri %]">
            [% whole.value.patron.firstname | html %] [% whole.value.patron.surname | html %] ([% whole.value.patron.cardnumber | html %])</a>
          </div>
        </li>
      </ol>
    </fieldset>

    <fieldset class="action">
      <input type="hidden" name="illrequest_id" id="illrequest_id" value="[% whole.illrequest_id | html %]" />
      <input type="hidden" name="backend" id="backend" value="[% request.backend | html %]" />
      <input type="hidden" name="method" id="method" value="return_to_library" />
      <input type="hidden" name="stage" id="stage" value="commit" />
      <input type="hidden" name="op" value="cud-return_to_library" />

      <button type="submit" class="btn btn-default approve">
        <i class="fa fa-check"></i> [% whole.strings.save | html %]
      </button>

      <button type="submit" class="btn btn-default openWin" data-url="/api/v1/contrib/slnp/ill_requests/[% whole.illrequest_id | uri %]/print_slips/ILL_PARTNER_RET" data-prevent-default="yes">
        <i class="fa fa-print"></i> [% whole.strings.save_and_print | html %]
      </button>

      <a class="cancel" id="cancelbutton" name="cancelbutton" href="/cgi-bin/koha/ill/ill-requests.pl?method=illview&amp;illrequest_id=[% request.illrequest_id | uri %]">[% whole.strings.cancel | html %]</a>

    </fieldset>
  </form>

<script>
    document.addEventListener('DOMContentLoaded', function() {
        $('#lending_library').select2();

        function Dopop(link) {
            var newin = window.open(link, 'popup', 'width=600,height=400,resizable=1,toolbar=0,scrollbars=1,top');
        }

        $('.openWin').on("click",function(e){
            Dopop( $(this).data("url") );

            if ( $(this).data("prevent-default" === 'yes' ) ) {
                e.preventDefault();
            }
        });
    });
</script>
