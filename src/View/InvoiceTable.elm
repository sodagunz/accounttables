module View.InvoiceTable exposing (Config, view)

import Accounting exposing (Currency(..), Movement, MovementType(..), SortDirection, SortField, currencyToString, descriptionDisplay)
import Html exposing (Html, button, div, p, section, span, table, tbody, td, text, th, thead, tr)
import Html.Attributes exposing (attribute, class, classList, type_)
import Html.Events exposing (onClick)
import InvoiceAllocation exposing (DocumentStatus(..))
import InvoiceReport
import Util.Date exposing (DateDisplay, formatDate)
import Util.Format exposing (formatMoney, formatNumber)


type alias Config msg =
    { allMovements : List Movement
    , invoices : List Movement
    , relatedCashflows : List Movement
    , dateDisplay : DateDisplay
    , displayCurrency : Currency
    , sortField : SortField
    , sortDirection : SortDirection
    , onSelectSort : SortField -> msg
    , onExportCsv : msg
    , onExportXlsx : msg
    , onDelete : String -> msg
    , onEdit : String -> msg
    }


view : Config msg -> Html msg
view config =
    let
        hasContent : Bool
        hasContent =
            not (List.isEmpty config.invoices) || not (List.isEmpty config.relatedCashflows)
    in
    section [ class "panel" ]
        [ Html.h2 [ class "section-title" ] [ text "Facturas y notas de crédito" ]
        , if hasContent then
            div [ class "expense-table-layout" ]
                [ invoiceTableBody config
                , exportControls config
                ]

          else
            p [ class "empty" ] [ text "Todavía no hay facturas ni notas de crédito para este período." ]
        ]


invoiceTableBody : Config msg -> Html msg
invoiceTableBody config =
    let
        report : InvoiceReport.Report
        report =
            InvoiceReport.build config.allMovements config.invoices config.relatedCashflows

        sortedRows : List InvoiceReport.DocumentRow
        sortedRows =
            List.sortBy (\document -> document.movement.date) report.rows

        summary : InvoiceReport.Summary
        summary =
            report.summary
    in
    div []
        [ div [ class "table-wrap" ]
            [ table [ class "expense-table invoice-table" ]
                [ thead []
                    [ tr []
                        [ th [] [ span [] [ text "Vencimiento" ] ]
                        , th [] [ span [] [ text "Tipo" ] ]
                        , th [] [ span [] [ text "Cuenta" ] ]
                        , th [] [ span [] [ text "Número" ] ]
                        , th [] [ span [] [ text "Descripción" ] ]
                        , th [] [ span [] [ text "Estado" ] ]
                        , th [ class "numeric" ] [ span [] [ text "Ingresado" ] ]
                        , th [ class "numeric" ] [ span [] [ text "Pendiente" ] ]
                        , th [ class "numeric" ] [ span [] [ text "Total" ] ]
                        , th [ class "actions-header" ] [ span [] [ text "Acciones" ] ]
                        ]
                    ]
                , tbody []
                    (List.map (row config.dateDisplay config.displayCurrency config.onEdit config.onDelete) sortedRows
                        ++ summaryRow "Total facturas" (valueForCurrency config.displayCurrency summary.facturasTotal) config.displayCurrency
                        ++ summaryRow "Total notas de crédito" (valueForCurrency config.displayCurrency summary.creditNotesTotal) config.displayCurrency
                        ++ summaryRow "Total documentos" (valueForCurrency config.displayCurrency summary.documentsTotal) config.displayCurrency
                        ++ summaryRow summary.settlementContributionLabel (valueForCurrency config.displayCurrency summary.settlementContribution) config.displayCurrency
                        ++ payableRow "Saldo pendiente" (valueForCurrency config.displayCurrency summary.payable) config.displayCurrency
                    )
                ]
            ]
        ]


row : DateDisplay -> Currency -> (String -> msg) -> (String -> msg) -> InvoiceReport.DocumentRow -> Html msg
row dateDisplay displayCurrency onEdit onDelete documentRow =
    let
        movement : Movement
        movement =
            documentRow.movement

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
    tr []
        [ td [ attribute "data-label" "Vencimiento" ] [ text (formatDate dateDisplay movement.date) ]
        , td [ attribute "data-label" "Tipo" ] [ text typeLabel ]
        , td [ attribute "data-label" "Cuenta" ] [ text movement.accountName ]
        , td [ attribute "data-label" "Número" ] [ text (movement.documentNumber |> Maybe.withDefault "-") ]
        , td [ attribute "data-label" "Descripción" ] [ text (descriptionDisplay movement) ]
        , td [ attribute "data-label" "Estado" ]
            [ span
                [ classList
                    [ ( "invoice-status", True )
                    , ( statusClass documentRow.settlement.status, True )
                    ]
                ]
                [ text documentRow.statusLabel ]
            ]
        , td [ attribute "data-label" "Ingresado", class "numeric" ] [ text (formatMoney movement.inputCurrency displayAmount) ]
        , td
            [ attribute "data-label" "Pendiente"
            , classList
                [ ( "numeric", True )
                , ( "is-negative", documentRow.settlement.remainingDue < 0 )
                ]
            ]
            [ text (formatMoney documentRow.settlement.currency documentRow.settlement.remainingDue) ]
        , td [ attribute "data-label" "Total", class "numeric" ] [ text (formatNumber (valueForCurrency displayCurrency movement)) ]
        , td [ class "action-cell", attribute "data-label" "" ]
            [ div [ class "action-buttons" ]
                [ button
                    [ type_ "button"
                    , class "edit-button"
                    , onClick (onEdit movement.id)
                    ]
                    [ text "✎" ]
                , button
                    [ type_ "button"
                    , class "delete-button"
                    , onClick (onDelete movement.id)
                    ]
                    [ text "×" ]
                ]
            ]
        ]


statusClass : DocumentStatus -> String
statusClass status =
    case status of
        Pending ->
            "invoice-status--pending"

        PartiallySettled ->
            "invoice-status--partial"

        FullySettled ->
            "invoice-status--full"

        OverSettled ->
            "invoice-status--over"


valueForCurrency : Currency -> { a | ars : Float, usd : Float } -> Float
valueForCurrency currency record =
    case currency of
        ARS ->
            record.ars

        USD ->
            record.usd


formatTotal : Float -> Currency -> String
formatTotal value currency =
    let
        number : String
        number =
            formatNumber value

        prefix : String
        prefix =
            currencyToString currency ++ " "
    in
    if String.startsWith "(" number then
        "(" ++ prefix ++ String.dropLeft 1 number

    else
        prefix ++ number


summaryRow : String -> Float -> Currency -> List (Html msg)
summaryRow label value displayCurrency =
    [ tr [ class "subtotal" ]
        [ td [ attribute "colspan" "8", attribute "data-label" label ] [ text label ]
        , td
            [ attribute "data-label" "Total"
            , classList
                [ ( "numeric", True )
                , ( "is-negative", value < 0 )
                ]
            ]
            [ text (formatTotal value displayCurrency) ]
        , td [] []
        ]
    ]


payableRow : String -> Float -> Currency -> List (Html msg)
payableRow label value displayCurrency =
    [ tr [ class "grand-total" ]
        [ td [ attribute "colspan" "8", attribute "data-label" label ] [ text label ]
        , td
            [ attribute "data-label" "Total"
            , classList
                [ ( "numeric", True )
                , ( "is-negative", value < 0 )
                ]
            ]
            [ text (formatTotal value displayCurrency) ]
        , td [] []
        ]
    ]


exportControls : Config msg -> Html msg
exportControls config =
    div [ class "report-options report-options--export" ]
        [ div [ class "segmented-control" ]
            [ span [ class "segmented-control__label" ] [ text "Exportar" ]
            , span
                [ class "segmented-control__option segmented-control__option--action"
                , onClick config.onExportCsv
                ]
                [ text "CSV" ]
            , span
                [ class "segmented-control__option segmented-control__option--action"
                , onClick config.onExportXlsx
                ]
                [ text "XLSX" ]
            ]
        ]
