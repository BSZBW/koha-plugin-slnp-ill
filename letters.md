# Benachrichtigungen Gebende Fernleihe

## AFL_ORDER_CREATED

Dieser Druck wird bei Eingangsverbuchung einer aktiven (gebenden) Fernleihe angestoßen, wenn in der Plugin-Konfiguration der Wert `accepted_afl_notice:1` gesetzt ist. Zusätzlich muss der Systemparameter `ILLDefaultStaffEmail` als Zieladresse der Benachrichtigung angegeben sein. 

### Message subject

`AFL Bestellung [% bestellid %]`

### Body

- email (ILLDefaultStaffEmail)

```
AFL Bestellung mit folgender BestellId eingegangen: [% bestellid %]

https://zfl-prod.bsz-bw.de/flcgi/zflhistory.pl?BestellId=[% bestellid %]

[% portal %]/flcgi/zflhistory.pl?BestellId=[% bestellid %]

AFL der nehmenden Bibliothek: [% pflnummer %]
```