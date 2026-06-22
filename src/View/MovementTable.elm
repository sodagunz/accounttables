module View.MovementTable exposing (Config, view)

import Accounting exposing (Account, Currency(..), FilterWindow(..), MoneyTotal, Movement, MovementType(..), SortDirection(..), SortField(..), currencyToString, descriptionDisplay, isInvoiceRelatedCashflow, movementsFor, summarizeMoney)
import Html exposing (Html, button, div, input, label, p, section, span, table, tbody, td, text, th, thead, tr)
import Html.Attributes exposing (attribute, checked, class, classList, for, id, name, type_)
import Html.Events exposing (onClick)
import Util.Date exposing (DateDisplay(..), formatDate)
import Util.Format exposing (formatMoney, formatNumber)


type alias Config msg =
    { expenses : List Movement
    , accounts : List Account
    , filterWindow : FilterWindow
    , hiddenAccountIds : List String
    , dateDisplay : DateDisplay
    , displayCurrency : Currency
    , showInputAmountColumn : Bool
    , showExchangeRateColumn : Bool
    , payable : MoneyTotal
    , sortField : SortField
    , sortDirection : SortDirection
    , onSelectFilter : FilterWindow -> msg
    , onToggleAccount : String -> msg
    , onSelectDateDisplay : DateDisplay -> msg
    , onSelectDisplayCurrency : Currency -> msg
    , onToggleShowInputAmountColumn : msg
    , onToggleShowExchangeRateColumn : msg
    , onSelectSort : SortField -> msg
    , onExportCsv : msg
    , onExportXlsx : msg
    , onDelete : String -> msg
    , onEdit : String -> msg
    , onSelectInvoiceView : msg
    }


view : Config msg -> Html msg
view config =
    section [ class "panel" ]
        [ Html.h2 [ class "section-title" ] [ text "Movimientos" ]
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
                    [ filterControls config
                    ]
                ]
            , expenseTableBody config
            ]
        ]


expenseTableBody : Config msg -> Html msg
expenseTableBody config =
    if List.isEmpty config.expenses then
        p [ class "empty" ] [ text "Todavía no hay movimientos para este período." ]

    else
        let
            visibleAccounts : List Account
            visibleAccounts =
                List.filter (\a -> not (List.member a.id config.hiddenAccountIds)) config.accounts
        in
        div []
            [ div [ class "table-wrap" ]
                [ table [ class "expense-table" ]
                    [ thead []
                        [ tr []
                            ([ sortableHeader config SortByDate "" "Fecha"
                             , sortableHeader config SortByAccount "" "Cuenta"
                             , sortableHeader config SortByDescription "" "Descripción"
                             ]
                                ++ (if config.showInputAmountColumn then
                                        [ th [ class "numeric" ] [ button [ type_ "button", class "non-sort-button" ] [ text "Ingresado" ] ] ]

                                    else
                                        []
                                   )
                                ++ (if config.showExchangeRateColumn then
                                        [ sortableHeader config SortByExchangeRate "numeric" "Cotización (USD/ARS)" ]

                                    else
                                        []
                                   )
                                ++ [ sortableHeader config
                                        (case config.displayCurrency of
                                            ARS ->
                                                SortByPesos

                                            USD ->
                                                SortByDollars
                                        )
                                        "numeric"
                                        (case config.displayCurrency of
                                            ARS ->
                                                "Total (ARS)"

                                            USD ->
                                                "Total (USD)"
                                        )
                                   , th [ class "actions-header" ] [ button [ type_ "button", class "non-sort-button" ] [ text "Acciones" ] ]
                                   ]
                            )
                        ]
                    , tbody [] (List.map (movementRow config.dateDisplay config.displayCurrency config.showInputAmountColumn config.showExchangeRateColumn config.onEdit config.onDelete) config.expenses ++ subtotalRows config visibleAccounts)
                    ]
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
        , div [ class "report-options report-options--columns" ]
            [ label [ class "column-toggle" ]
                [ input [ type_ "checkbox", checked config.showInputAmountColumn, onClick config.onToggleShowInputAmountColumn ] []
                , span [] [ text "Mostrar ingresado" ]
                ]
            , label [ class "column-toggle" ]
                [ input [ type_ "checkbox", checked config.showExchangeRateColumn, onClick config.onToggleShowExchangeRateColumn ] []
                , span [] [ text "Mostrar cotización" ]
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


movementRow : DateDisplay -> Currency -> Bool -> Bool -> (String -> msg) -> (String -> msg) -> Movement -> Html msg
movementRow dateDisplay displayCurrency showInputAmountColumn showExchangeRateColumn onEdit onDelete movement =
    let
        totalValue : Float
        totalValue =
            valueForCurrency displayCurrency movement

        isConverted : Bool
        isConverted =
            movement.inputCurrency /= displayCurrency
    in
    tr []
        ([ td [ attribute "data-label" "Fecha" ] [ text (formatDate dateDisplay movement.date) ]
         , td [ attribute "data-label" "Cuenta" ] [ text movement.accountName ]
         , td [ attribute "data-label" "Descripción" ]
            [ span [] [ text (descriptionDisplay movement) ]
            , if isInvoiceRelatedCashflow movement then
                span [ class "invoice-badge" ] [ text "Factura" ]

              else
                text ""
            ]
         ]
            ++ (if showInputAmountColumn then
                    let
                        displayAmount : Float
                        displayAmount =
                            case movement.movementType of
                                ExpenseMovement ->
                                    -movement.inputAmount

                                IncomeMovement ->
                                    movement.inputAmount

                                SupplierInvoiceMovement ->
                                    -movement.inputAmount

                                SupplierCreditNoteMovement ->
                                    movement.inputAmount
                    in
                    [ td [ attribute "data-label" "Ingresado", class "numeric" ] [ text (formatMoney movement.inputCurrency displayAmount) ] ]

                else
                    []
               )
            ++ (if showExchangeRateColumn then
                    [ td [ attribute "data-label" "Cotización", class "numeric" ] [ text (formatMoney ARS movement.exchangeRate) ] ]

                else
                    []
               )
            ++ [ td
                    [ attribute "data-label" "Total"
                    , classList
                        [ ( "numeric", True )
                        , ( "movement-total", True )
                        , ( "movement-total--converted", isConverted )
                        ]
                    ]
                    [ span [ class "movement-total__value" ] [ text (formatMoney displayCurrency totalValue) ]
                    , if isConverted then
                        span [ class "movement-total__badge" ] [ text ("Convertido a " ++ formatNumber movement.exchangeRate ++ " ARS/USD") ]

                      else
                        text ""
                    ]
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
                            , attribute "data-tutorial" ("delete-" ++ movement.id)
                            , onClick (onDelete movement.id)
                            ]
                            [ text "×" ]
                        ]
                    ]
               ]
        )


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


sortableHeader : Config msg -> SortField -> String -> String -> Html msg
sortableHeader config sortField alignment labelText =
    let
        active : Bool
        active =
            config.sortField == sortField

        sortIndicator : String
        sortIndicator =
            if active then
                case config.sortDirection of
                    Ascending ->
                        " ▲"

                    Descending ->
                        " ▼"

            else
                ""
    in
    th [ class alignment ]
        [ button
            [ type_ "button"
            , class
                (if active then
                    "sort-button sort-button--active"

                 else
                    "sort-button"
                )
            , onClick (config.onSelectSort sortField)
            ]
            [ text (labelText ++ sortIndicator) ]
        ]


subtotalRows : Config msg -> List Account -> List (Html msg)
subtotalRows config accounts =
    let
        cashOnHand : MoneyTotal
        cashOnHand =
            summarizeMoney config.expenses

        total : MoneyTotal
        total =
            { ars = cashOnHand.ars + config.payable.ars
            , usd = cashOnHand.usd + config.payable.usd
            }
    in
    List.map (\account -> totalRow config.displayCurrency config.showInputAmountColumn config.showExchangeRateColumn (text ("Subtotal " ++ account.name)) "subtotal" Nothing (summarizeMoney (movementsFor account config.expenses))) accounts
        ++ [ totalRow config.displayCurrency
                config.showInputAmountColumn
                config.showExchangeRateColumn
                (text "Saldo pendiente (facturas)")
                "summary-divider subtotal clickable-summary-row"
                (Just config.onSelectInvoiceView)
                config.payable
           , totalRow config.displayCurrency config.showInputAmountColumn config.showExchangeRateColumn (text "Saldo de caja (movimientos)") "subtotal" Nothing cashOnHand
           , totalRow config.displayCurrency config.showInputAmountColumn config.showExchangeRateColumn (text "Posición neta") "grand-total" Nothing total
           ]


totalRow : Currency -> Bool -> Bool -> Html msg -> String -> Maybe msg -> MoneyTotal -> Html msg
totalRow displayCurrency showInputAmountColumn showExchangeRateColumn labelContent rowClass onSelect total =
    let
        totalValue : Float
        totalValue =
            valueForCurrency displayCurrency total

        valueColumnOffset : Int
        valueColumnOffset =
            3
                + (if showInputAmountColumn then
                    1

                   else
                    0
                  )
                + (if showExchangeRateColumn then
                    1

                   else
                    0
                  )
    in
    tr
        (class rowClass
            :: (case onSelect of
                    Just msg ->
                        [ onClick msg ]

                    Nothing ->
                        []
               )
        )
        [ td [ attribute "colspan" (String.fromInt valueColumnOffset), attribute "data-label" "Total" ] [ labelContent ]
        , td
            [ attribute "data-label" "Total"
            , classList
                [ ( "numeric", True )
                , ( "is-negative", totalValue < 0 )
                ]
            ]
            [ text (formatTotal totalValue displayCurrency) ]
        , td [ attribute "data-label" "" ] []
        ]
