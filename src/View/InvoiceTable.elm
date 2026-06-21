module View.InvoiceTable exposing (Config, view)

import Accounting exposing (Account, Currency(..), FilterWindow(..), MoneyTotal, Movement, MovementType(..), SortDirection, SortField, currencyToString, descriptionDisplay, summarizeMoney)
import Html exposing (Html, button, div, input, label, p, section, span, table, tbody, td, text, th, thead, tr)
import Html.Attributes exposing (attribute, checked, class, classList, for, id, name, type_)
import Html.Events exposing (onClick)
import InvoiceAllocation exposing (DocumentStatus(..))
import InvoiceReport
import Util.Date exposing (DateDisplay(..), formatDate)
import Util.Format exposing (formatMoney, formatNumber)


type alias Config msg =
    { allMovements : List Movement
    , invoices : List Movement
    , relatedCashflows : List Movement
    , cashflowMovements : List Movement
    , accounts : List Account
    , filterWindow : FilterWindow
    , hiddenAccountIds : List String
    , dateDisplay : DateDisplay
    , displayCurrency : Currency
    , sortField : SortField
    , sortDirection : SortDirection
    , onSelectFilter : FilterWindow -> msg
    , onToggleAccount : String -> msg
    , onSelectDateDisplay : DateDisplay -> msg
    , onSelectDisplayCurrency : Currency -> msg
    , onSelectSort : SortField -> msg
    , onExportCsv : msg
    , onExportXlsx : msg
    , onDelete : String -> msg
    , onEdit : String -> msg
    , onSelectMovementsView : msg
    }


view : Config msg -> Html msg
view config =
    section [ class "panel" ]
        [ Html.h2 [ class "section-title" ] [ text "Facturas" ]
        , div [ class "expense-table-layout" ]
            [ div [ class "filters-toggle" ]
                [ input
                    [ type_ "checkbox"
                    , id "filters-toggle-input"
                    , class "filters-toggle__input"
                    ]
                    []
                , label
                    [ class "filters-toggle__button"
                    , for "filters-toggle-input"
                    ]
                    [ span [] [ text "Filtros" ]
                    , span [ class "filters-toggle__arrow" ] [ text "▼" ]
                    ]
                , div [ class "filters-toggle__content" ]
                    [ filterControls config ]
                ]
            , invoiceTableBody config
            ]
        ]


invoiceTableBody : Config msg -> Html msg
invoiceTableBody config =
    let
        hasContent : Bool
        hasContent =
            not (List.isEmpty config.invoices) || not (List.isEmpty config.relatedCashflows)
    in
    if hasContent then
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
                            ++ summaryRow "Total facturas" (text "Total facturas") "subtotal" Nothing (valueForCurrency config.displayCurrency summary.facturasTotal) config.displayCurrency
                            ++ summaryRow "Total notas de crédito" (text "Total notas de crédito") "subtotal" Nothing (valueForCurrency config.displayCurrency summary.creditNotesTotal) config.displayCurrency
                            ++ summaryRow "Total documentos" (text "Total documentos") "subtotal" Nothing (valueForCurrency config.displayCurrency summary.documentsTotal) config.displayCurrency
                            ++ summaryRow summary.settlementContributionLabel (text summary.settlementContributionLabel) "subtotal" Nothing (valueForCurrency config.displayCurrency summary.settlementContribution) config.displayCurrency
                            ++ sharedSummaryRows config summary.payable
                        )
                    ]
                ]
            ]

    else
        p [ class "empty" ] [ text "Todavía no hay facturas para este período." ]


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


summaryRow : String -> Html msg -> String -> Maybe msg -> Float -> Currency -> List (Html msg)
summaryRow dataLabel labelContent rowClass onSelect value displayCurrency =
    [ tr
        (class rowClass
            :: (case onSelect of
                    Just msg ->
                        [ onClick msg ]

                    Nothing ->
                        []
               )
        )
        [ td [ attribute "colspan" "8", attribute "data-label" dataLabel ] [ labelContent ]
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


sharedSummaryRows : Config msg -> MoneyTotal -> List (Html msg)
sharedSummaryRows config payable =
    let
        cashOnHand : MoneyTotal
        cashOnHand =
            summarizeMoney config.cashflowMovements

        total : MoneyTotal
        total =
            { ars = cashOnHand.ars + payable.ars
            , usd = cashOnHand.usd + payable.usd
            }
    in
    summaryRow
        "Saldo pendiente (facturas)"
        (text "Saldo pendiente (facturas)")
        "summary-divider subtotal"
        Nothing
        (valueForCurrency config.displayCurrency payable)
        config.displayCurrency
        ++ summaryRow
            "Saldo de caja (movimientos)"
            (text "Saldo de caja (movimientos)")
            "subtotal clickable-summary-row"
            (Just config.onSelectMovementsView)
            (valueForCurrency config.displayCurrency cashOnHand)
            config.displayCurrency
        ++ [ tr [ class "grand-total" ]
                [ td [ attribute "colspan" "8", attribute "data-label" "Posición neta" ] [ text "Posición neta" ]
                , td
                    [ attribute "data-label" "Posición neta"
                    , classList
                        [ ( "numeric", True )
                        , ( "is-negative", valueForCurrency config.displayCurrency total < 0 )
                        ]
                    ]
                    [ text (formatTotal (valueForCurrency config.displayCurrency total) config.displayCurrency) ]
                , td [] []
                ]
           ]


filterControls : Config msg -> Html msg
filterControls config =
    div [ class "filters" ]
        [ div [ class "report-options" ]
            [ div [ class "segmented-control" ]
                [ span [ class "segmented-control__label" ] [ text "Filtros" ]
                , filterSegment config AllTime "Completo"
                , filterSegment config ThisYear "Año"
                , filterSegment config ThisMonth "Mes"
                , filterSegment config ThisWeek "Semana"
                , filterSegment config Today "Día"
                ]
            ]
        , div [ class "report-options" ]
            [ div [ class "segmented-control" ]
                (span [ class "segmented-control__label" ] [ text "Cuenta" ]
                    :: List.map (accountSegment config) config.accounts
                )
            ]
        , div [ class "report-options" ]
            [ div [ class "segmented-control" ]
                [ span [ class "segmented-control__label" ] [ text "Fecha" ]
                , dateSegment config NumericDate "DD/MM/AAAA"
                , dateSegment config LongDate "Texto"
                ]
            ]
        , div [ class "report-options" ]
            [ div [ class "segmented-control" ]
                [ span [ class "segmented-control__label" ] [ text "Divisa" ]
                , radioSegment config.onSelectDisplayCurrency ARS (config.displayCurrency == ARS) "ARS"
                , radioSegment config.onSelectDisplayCurrency USD (config.displayCurrency == USD) "USD"
                ]
            ]
        , exportControls config
        ]


filterSegment : Config msg -> FilterWindow -> String -> Html msg
filterSegment config filterWindow labelText =
    label
        [ classList
            [ ( "segmented-control__option", True )
            , ( "segmented-control__option--active", config.filterWindow == filterWindow )
            ]
        ]
        [ input
            [ type_ "radio"
            , name "filter-window"
            , checked (config.filterWindow == filterWindow)
            , onClick (config.onSelectFilter filterWindow)
            ]
            []
        , span [] [ text labelText ]
        ]


dateSegment : Config msg -> DateDisplay -> String -> Html msg
dateSegment config dateDisplay labelText =
    label
        [ classList
            [ ( "segmented-control__option", True )
            , ( "segmented-control__option--active", config.dateDisplay == dateDisplay )
            ]
        ]
        [ input
            [ type_ "radio"
            , name "date-display"
            , checked (config.dateDisplay == dateDisplay)
            , onClick (config.onSelectDateDisplay dateDisplay)
            ]
            []
        , span [] [ text labelText ]
        ]


radioSegment : (a -> msg) -> a -> Bool -> String -> Html msg
radioSegment onChange value isActive labelText =
    label
        [ classList
            [ ( "segmented-control__option", True )
            , ( "segmented-control__option--active", isActive )
            ]
        ]
        [ input
            [ type_ "radio"
            , name "segmented-radio"
            , checked isActive
            , onClick (onChange value)
            ]
            []
        , span [] [ text labelText ]
        ]


accountSegment : Config msg -> Account -> Html msg
accountSegment config account =
    let
        hidden : Bool
        hidden =
            List.member account.id config.hiddenAccountIds
    in
    label
        [ classList
            [ ( "segmented-control__option", True )
            , ( "segmented-control__option--active", not hidden )
            ]
        ]
        [ input
            [ type_ "checkbox"
            , checked (not hidden)
            , onClick (config.onToggleAccount account.id)
            ]
            []
        , span [] [ text account.name ]
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
