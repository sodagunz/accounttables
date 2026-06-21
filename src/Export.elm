module Export exposing (Format(..), invoiceTablePayload, tablePayload)

import Accounting exposing (Account, Currency(..), MoneyTotal, Movement, MovementType(..), descriptionDisplay, invoiceTotal, movementsFor, negateMoney, summarizeMoney)
import Json.Encode as Encode
import Util.Date exposing (DateDisplay, formatDate)
import Util.Format exposing (formatMoney)


type Format
    = Csv
    | Xlsx


type alias TableRow =
    { label : String
    , cells : List String
    }


tablePayload : Format -> DateDisplay -> String -> List Account -> List Movement -> Encode.Value
tablePayload format dateDisplay today accounts movements =
    Encode.object
        [ ( "format", Encode.string (formatToString format) )
        , ( "filename", Encode.string (filename format today) )
        , ( "sheetName", Encode.string "Gastos" )
        , ( "headers", Encode.list Encode.string headers )
        , ( "rows", Encode.list rowEncoder (movementRows dateDisplay movements ++ subtotalRows accounts movements) )
        ]


formatToString : Format -> String
formatToString format =
    case format of
        Csv ->
            "csv"

        Xlsx ->
            "xlsx"


filename : Format -> String -> String
filename format today =
    "accounttables-gastos-"
        ++ today
        ++ (case format of
                Csv ->
                    ".csv"

                Xlsx ->
                    ".xlsx"
           )


headers : List String
headers =
    [ "Fecha"
    , "Cuenta"
    , "Descripción"
    , "Ingresado"
    , "Cotización (USD/ARS)"
    , "Pesos (ARS)"
    , "Dólar (USD)"
    ]


movementRows : DateDisplay -> List Movement -> List TableRow
movementRows dateDisplay movements =
    List.map (movementRow dateDisplay) movements


movementRow : DateDisplay -> Movement -> TableRow
movementRow dateDisplay movement =
    { label = "movement"
    , cells =
        [ formatDate dateDisplay movement.date
        , movement.accountName
        , descriptionDisplay movement
        , formatMoney movement.inputCurrency movement.inputAmount
        , formatMoney ARS movement.exchangeRate
        , formatMoney ARS movement.ars
        , formatMoney USD movement.usd
        ]
    }


subtotalRows : List Account -> List Movement -> List TableRow
subtotalRows accounts movements =
    let
        grandTotal : MoneyTotal
        grandTotal =
            summarizeMoney movements
    in
    List.map (\account -> totalRow ("Subtotal " ++ account.name) "subtotal" (summarizeMoney (movementsFor account movements))) accounts
        ++ [ totalRow "Total" "total" grandTotal ]


totalRow : String -> String -> MoneyTotal -> TableRow
totalRow labelText label total =
    { label = label
    , cells =
        [ labelText
        , ""
        , ""
        , ""
        , ""
        , formatMoney ARS total.ars
        , formatMoney USD total.usd
        ]
    }


invoiceTablePayload : Format -> DateDisplay -> String -> List Movement -> List Movement -> Encode.Value
invoiceTablePayload format dateDisplay today invoices relatedCashflows =
    Encode.object
        [ ( "format", Encode.string (formatToString format) )
        , ( "filename", Encode.string (invoicesFilename format today) )
        , ( "sheetName", Encode.string "Facturas" )
        , ( "headers", Encode.list Encode.string invoiceHeaders )
        , ( "rows", Encode.list rowEncoder (invoiceRows dateDisplay invoices ++ invoiceSummaryRows invoices relatedCashflows) )
        ]


invoicesFilename : Format -> String -> String
invoicesFilename format today =
    "accounttables-facturas-"
        ++ today
        ++ (case format of
                Csv ->
                    ".csv"

                Xlsx ->
                    ".xlsx"
           )


invoiceHeaders : List String
invoiceHeaders =
    [ "Vencimiento"
    , "Tipo"
    , "Cuenta"
    , "Número"
    , "Descripción"
    , "Ingresado"
    , "Cotización (USD/ARS)"
    , "Pesos (ARS)"
    , "Dólar (USD)"
    ]


invoiceRows : DateDisplay -> List Movement -> List TableRow
invoiceRows dateDisplay movements =
    List.map (invoiceRow dateDisplay) movements


invoiceRow : DateDisplay -> Movement -> TableRow
invoiceRow dateDisplay movement =
    let
        displayAmount : Float
        displayAmount =
            case movement.movementType of
                SupplierInvoiceMovement ->
                    -movement.inputAmount

                SupplierCreditNoteMovement ->
                    movement.inputAmount

                _ ->
                    movement.inputAmount

        typeLabel : String
        typeLabel =
            case movement.movementType of
                SupplierInvoiceMovement ->
                    "Factura"

                SupplierCreditNoteMovement ->
                    "Nota de crédito"

                _ ->
                    ""
    in
    { label = "invoice"
    , cells =
        [ formatDate dateDisplay movement.date
        , typeLabel
        , movement.accountName
        , movement.documentNumber |> Maybe.withDefault ""
        , descriptionDisplay movement
        , formatMoney movement.inputCurrency displayAmount
        , formatMoney ARS movement.exchangeRate
        , formatMoney ARS movement.ars
        , formatMoney USD movement.usd
        ]
    }


invoiceSummaryRows : List Movement -> List Movement -> List TableRow
invoiceSummaryRows invoices relatedCashflows =
    let
        facturasTotal : MoneyTotal
        facturasTotal =
            invoices
                |> List.filter (\m -> m.movementType == SupplierInvoiceMovement)
                |> summarizeMoney

        creditNotesTotal : MoneyTotal
        creditNotesTotal =
            invoices
                |> List.filter (\m -> m.movementType == SupplierCreditNoteMovement)
                |> summarizeMoney

        invoiceSum : MoneyTotal
        invoiceSum =
            summarizeMoney invoices

        paymentSum : MoneyTotal
        paymentSum =
            summarizeMoney relatedCashflows

        payable : MoneyTotal
        payable =
            invoiceTotal invoices relatedCashflows
    in
    [ summaryRow "Total facturas" facturasTotal
    , summaryRow "Total notas de crédito" creditNotesTotal
    , summaryRow "Total documentos" invoiceSum
    , summaryRow "Movimientos relacionados" (negateMoney paymentSum)
    , summaryRow "A pagar" payable
    ]


summaryRow : String -> MoneyTotal -> TableRow
summaryRow labelText total =
    { label = "summary"
    , cells =
        [ labelText
        , ""
        , ""
        , ""
        , ""
        , ""
        , ""
        , formatMoney ARS total.ars
        , formatMoney USD total.usd
        ]
    }


rowEncoder : TableRow -> Encode.Value
rowEncoder row =
    Encode.object
        [ ( "type", Encode.string row.label )
        , ( "cells", Encode.list Encode.string row.cells )
        ]
