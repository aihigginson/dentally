# Self-billing agreement

**Template — one signed copy per partner. Not published on the website.**

This is the agreement HMRC requires *before* the first self-billed invoice is raised. It is not a
trust document for the public docs allowlist: it is bilateral, it is signed, and it carries the
partner's own VAT number and address.

> **Why it has to exist before you pay anyone.** VAT Notice 700/62: a self-billed VAT invoice may
> only be issued where a written self-billing agreement is already in place; it must show the
> supplier's name, address and VAT registration number; and it may not be issued at all to a
> supplier who is not VAT registered, or whose VAT number has changed since the agreement.
> `Billing.Affiliate.Self_Bill_Agreed_On` records the date signed, and `Can_Self_Bill` stays false
> until both that date and the VAT position are known.
>
> The first partner channel is the NASDAL directory — specialist dental accountants. If the
> paperwork is wrong, that is the audience who will notice.
>
> This is a working template, not legal advice. Worth ten minutes of an accountant's time before
> the first one goes out — and you will shortly be talking to thirty-three of them.

---

## Self-billing agreement

**Between:**

**Analytically Limited** (company no. 16242443), whose registered office is at
`[REGISTERED OFFICE ADDRESS]`, VAT registration number `[ANALYTICALLY VAT NUMBER]`
— "the Customer", who will raise the invoices.

**and**

`[PARTNER LEGAL NAME]`, `[company/LLP number, if applicable]`, whose address is
`[PARTNER ADDRESS]`, VAT registration number `[PARTNER VAT NUMBER]`
— "the Supplier", who will receive the payments.

**Dated:** `[DATE]`

### 1. What this covers

Commission payable by the Customer to the Supplier for introducing dental practices to the
Customer's Analytically service, under the partner terms in force between them.

### 2. The Customer will

1. Issue self-billed invoices for all commission due under those partner terms, for the period in
   clause 5.
2. Include on each self-billed invoice the Supplier's name, address and VAT registration number,
   together with all other particulars required for a full VAT invoice.
3. Send a copy of each self-billed invoice to the Supplier, and keep a copy.
4. Raise a new self-billing agreement if the Supplier's VAT registration number changes.

### 3. The Supplier will

1. **Not raise VAT invoices** for the supplies covered by this agreement.
2. **Accept** each self-billed invoice raised by the Customer under it.
3. **Tell the Customer at once** if the Supplier ceases to be VAT registered, if the VAT
   registration number changes, or if the business is transferred as a going concern.

### 4. Payment

Commission is calculated monthly on amounts **actually collected** from the introduced practice,
at the rate in the partner terms (standard rate 20%). Payment is by bank transfer to:

- Account name: `[ACCOUNT NAME]`
- Sort code: `[SORT CODE]`
- Account number: `[ACCOUNT NUMBER]`

Commission accrues when the practice is invoiced and becomes payable once that invoice is paid. If
an invoice is later credited, the commission on the credited amount is deducted from the next
statement.

### 5. Period

This agreement runs for **12 months** from the date above, and may be renewed for further periods
by agreement. Either party may end it by written notice, and it ends automatically if the Supplier
ceases to be VAT registered.

### 6. Signatures

| | Customer | Supplier |
|---|---|---|
| **Signed** | | |
| **Name** | | |
| **Position** | | |
| **Date** | | |

---

### Before sending

- [ ] Analytically's own VAT number and registered office filled in
- [ ] Partner's legal name, address and VAT number confirmed **in writing** by them
- [ ] Bank details confirmed by the partner, not taken from an email footer
- [ ] Once signed: record `Self_Bill_Agreed_On`, `VAT_Number`, `Is_VAT_Registered`, `Address` and
      the bank details against the affiliate, so `Can_Self_Bill` turns true

### If the partner is not VAT registered

Do not issue a self-billed VAT invoice. Pay against a plain commission statement with no VAT shown,
and set `Is_VAT_Registered = 0` so the distinction is recorded rather than looking like an
unanswered question.
