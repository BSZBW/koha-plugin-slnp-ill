[% USE raw %]
[% USE Asset %]
[% SET footerjs = 1 %]

[% USE Koha %]
[% USE AuthorisedValues %]
[% USE ItemTypes %]
[% USE KohaDates %]
[% USE Price %]

[% IF whole.error %]
  [% IF whole.status == 'missing_sendingIllLibraryInfo' %]
    <p>[% whole.strings.lending_library_missing | html %].</p>
  [% ELSE %]
    <p>[% whole.strings.unknown_error | html %]</p>
  [% END %]
[% END %]

[% IF whole.stage == 'init' %]
  <h2> [% whole.strings.update_request | html %] ([% request.orderid | html %])</h2>

  <form id="SLNP_delivery" name="SLNP_delivery" method="POST" action=[% here %]>

    <fieldset class="rows">
      <legend>[% whole.strings.title | html %]</legend>
      <ol id="general-slnp_delivery-fields">

        <li>
          <label class="required" for="type">[% whole.strings.request_type | html %]:</label>
            <select name="type" id="type" required="required">
            [% IF whole.value.medium == "loan" %]
              <option value="loan" selected="selected">[% whole.strings.loan | html %]</option>
            [% ELSE %]
              <option value="loan">[% whole.strings.loan | html %]</option>
            [% END %]
            [% IF whole.value.medium == "copy" %]
              <option value="copy" selected="selected">[% whole.strings.copy | html %]</option>
            [% ELSE %]
              <option value="copy">[% whole.strings.copy | html %]</option>
            [% END %]
          </select>
        </li>

        <li>
          <label class="required" for="received_on_date">[% whole.strings.received_on | html %]:</label>
          <input type="text" class="flatpickr" name="received_on_date" id="received_on_date" size="10" maxlength="10" value="[% whole.value.received_on_date %]" required="required" />
          <span class="hint">[% INCLUDE 'date-format.inc' %]</span>
        </li>

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

        <li>
          <label for="request_charges">[% whole.strings.cost | html %]:</label>
        [% IF whole.value.disable_extra_fee %]
          <input type="text" inputmode="decimal" pattern="^\d+(\.\d{2})?$" size="10" name="request_charges" id="request_charges" value="[% whole.value.request_charges | $Price on_editing => 1 %]" readonly />
          <input type="checkbox" id="charge_extra_fee" name="charge_extra_fee" disabled="disabled" checked="checked" />
        [% ELSE %]
          <input type="text" inputmode="decimal" pattern="^\d+(\.\d{2})?$" size="10" name="request_charges" id="request_charges" value="[% whole.value.request_charges | $Price on_editing => 1 %]" />
          <input type="checkbox" id="charge_extra_fee" name="charge_extra_fee" />
          <input type="hidden" id="set_extra_fee" name="set_extra_fee" value="1" />
        [% END %]
          <span>[% whole.strings.charge_patron | html %]</span>
        </li>

        <li>
          <label for="circulation_notes">[% whole.strings.circulation_restrictions | html %]:</label>
          <input type="text" size="50" name="circulation_notes" id="circulation_notes" value="[% whole.value.circulation_notes | html %]" />
        </li>

      </ol>
    </fieldset>

    <fieldset class="rows">
    <legend>[% whole.strings.item | html %]</legend>
      <ol>
        <li>
          <label for="item_callnumber">[% whole.strings.item_callnumber | html %]:</label>
          <input type="text" size="50" name="item_callnumber" id="item_callnumber" value="[% whole.value.item.itemcallnumber | html %]" />
        </li>

        <li>
          <label for="item_number_of_parts">[% whole.strings.item_num_parts | html %]:</label>
          <input type="text" size="50" name="item_number_of_parts" id="item_number_of_parts" value="[% whole.value.item.materials | html %]" />
        </li>

        <li>
          <label for="item_usage_restrictions">[% whole.strings.item_usage_restrictions | html %]:</label>
          [% PROCESS 'av-build-dropbox.inc' name="item_usage_restrictions", category="RESTRICTED", empty=1, default=whole.value.item.restricted %]
        </li>

        <li>
          <label for="item_damaged">[% whole.strings.item_damaged | html %]:</label>
          [% PROCESS 'av-build-dropbox.inc' name="item_damaged", category="DAMAGED", empty=1, default=whole.value.item.damaged %]
        </li>

        <li>
          <label for="item_internal_note">[% whole.strings.item_internal_note | html %]:</label>
          <input type="text" size="50" name="item_internal_note" id="item_internal_note" value="[% whole.value.item.itemnotes_nonpublic | html %]" />
        </li>

        <li>
          <label for="due_date">[% whole.strings.item_due_date | html %]:</label>
          <input type="text" class="flatpickr" name="due_date" id="due_date" size="10" maxlength="10" value="[% whole.value.due_date %]" />
         <span class="hint">[% INCLUDE 'date-format.inc' %]</span>
        </li>

      </ol>
    </fieldset>

    <fieldset class="rows">
    <legend>[% whole.strings.request | html %]</legend>
      <ol>
        <li>
          <label for="opac_note">[% whole.strings.request_opac_note | html %]:</label>
          <textarea id="opac_note" name="opac_note" rows="4" cols="50">[% whole.value.opac_note | html %]</textarea>
        </li>

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
            <a target="_blank" href="/cgi-bin/koha/members/moremember.pl?borrowernumber=[% whole.value.patron.borrowernumber %]">
            [% whole.value.patron.firstname | html %] [% whole.value.patron.surname | html %] ([% whole.value.patron.cardnumber | html %])</a>
          </div>
        </li>
      </ol>
    </fieldset>

    <fieldset class="action">
      <input type="hidden" name="illrequest_id" id="illrequest_id" value="[% whole.illrequest_id | html %]" />
      <input type="hidden" name="backend" id="backend" value="[% request.backend | html %]" />
      <input type="hidden" name="method" id="method" value="update" />
      <input type="hidden" name="stage" id="stage" value="commit" />
      <input type="hidden" name="itemnumber" id="itemnumber" value="[% whole.value.other.itemnumber | html%]" />
      <input type="hidden" name="op" id="op" value="cud-update" />

      <button type="submit" class="btn btn-default approve">
        <i class="fa fa-check"></i> [% whole.strings.update | html %]
      </button>

      <button type="submit" class="btn btn-default openWin" data-url="/api/v1/contrib/slnp/ill_requests/[% whole.illrequest_id | uri %]/print_slips/ILL_RECEIVE_SLIP" data-prevent-default="yes">
        <i class="fa fa-print"></i> [% whole.strings.print_and_update | html %]
      </button>

      <a class="cancel" id="cancelbutton" name="cancelbutton" href="/cgi-bin/koha/ill/ill-requests.pl?method=illview&amp;illrequest_id=[% request.illrequest_id | uri %]">[% whole.strings.cancel | html %]</a>

    </fieldset>
  </form>

[% ELSE %]
  <p>[% whole.strings.unknown_stage | html %]: '[% whole.stage %]'</p>
[% END %]

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
