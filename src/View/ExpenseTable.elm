module View.ExpenseTable exposing (Config, view)

import Accounting exposing (Account, Currency(..), Expense, FilterWindow(..), MoneyTotal, MovementType(..), SortDirection(..), SortField(..), currencyToString, descriptionDisplay, expensesFor, summarizeMoney)
import Html exposing (Html, button, div, input, label, p, section, span, table, tbody, td, text, th, thead, tr)
import Html.Attributes exposing (attribute, checked, class, classList, for, id, name, type_, value)
import Html.Events exposing (onClick)
import Util.Date exposing (DateDisplay(..), formatDate)
import Util.Format exposing (formatMoney, formatNumber)


type alias Config msg =
    { expenses : List Expense
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
    ,             onDelete : String -> msg
            , onEdit : String -> msg
    }


view : Config msg -> Html msg
view config =
    section [ class "panel" ]
        [ Html.h2 [ class "section-title" ] [ text "Gastos" ]
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
        p [ class "empty" ] [ text "Todavía no hay gastos." ]

    else
        let
            visibleAccounts =
                List.filter (\a -> not (List.member a.id config.hiddenAccountIds)) config.accounts
        in
        div []
            [ div [ class "table-wrap" ]
                [ table [ class "expense-table" ]
                    [ thead []
                        [ tr []
                            [ sortableHeader config SortByDate "" "Fecha"
                            , sortableHeader config SortByAccount "" "Caja"
                            , sortableHeader config SortByDescription "" "Descripción"
                            , th [ class "numeric" ] [ button [ type_ "button", class "non-sort-button" ] [ text "Ingresado" ] ]
                            , sortableHeader config SortByExchangeRate "numeric" "Cotización (USD/ARS)"
                            , sortableHeader config
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
                            ]
                        ]
                    , tbody [] (List.map (expenseRow config.dateDisplay config.displayCurrency config.onEdit config.onDelete) config.expenses ++ subtotalRows visibleAccounts config.expenses config.displayCurrency)
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
                ([ span [ class "segmented-control__label" ] [ text "Caja" ] ]
                    ++ List.map (accountSegment config) config.accounts
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


expenseRow : DateDisplay -> Currency -> (String -> msg) -> (String -> msg) -> Expense -> Html msg
expenseRow dateDisplay displayCurrency onEdit onDelete expense =
    tr []
        [ td [ attribute "data-label" "Fecha" ] [ text (formatDate dateDisplay expense.date) ]
        , td [ attribute "data-label" "Caja" ] [ text expense.accountName ]
        , td [ attribute "data-label" "Descripción" ] [ text (descriptionDisplay expense) ]
        , let
            displayAmount =
                case expense.movementType of
                    ExpenseMovement ->
                        -expense.inputAmount

                    IncomeMovement ->
                        expense.inputAmount
          in
          td [ attribute "data-label" "Ingresado", class "numeric" ] [ text (formatMoney expense.inputCurrency displayAmount) ]
        , td [ attribute "data-label" "Cotización", class "numeric" ] [ text (formatNumber expense.exchangeRate) ]
        , td [ attribute "data-label" "Total", class "numeric" ] [ text (formatNumber (valueForCurrency displayCurrency expense)) ]
        , td [ class "action-cell" ]
            [ button
                [ type_ "button"
                , class "edit-button"
                , onClick (onEdit expense.id)
                ]
                [ text "✎" ]
            , button
                [ type_ "button"
                , class "delete-button"
                , onClick (onDelete expense.id)
                ]
                [ text "×" ]
            ]
        ]


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
        number =
            formatNumber value

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
        active =
            config.sortField == sortField

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


subtotalRows : List Account -> List Expense -> Currency -> List (Html msg)
subtotalRows accounts expenses displayCurrency =
    let
        grandTotal =
            summarizeMoney expenses
    in
    List.map (\account -> totalRow displayCurrency ("Subtotal " ++ account.name) "subtotal" (summarizeMoney (expensesFor account expenses))) accounts
        ++ [ totalRow displayCurrency "Total" "grand-total" grandTotal ]


totalRow : Currency -> String -> String -> MoneyTotal -> Html msg
totalRow displayCurrency labelText rowClass total =
    tr [ class rowClass ]
        [ td [ attribute "colspan" "5", attribute "data-label" "Total" ] [ text labelText ]
        , td [ attribute "data-label" "Total", class "numeric" ] [ text (formatTotal (valueForCurrency displayCurrency total) displayCurrency) ]
        ]
