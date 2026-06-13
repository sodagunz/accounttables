module View.ExpenseTable exposing (Config, view)

import Accounting exposing (Account, Currency(..), Expense, FilterWindow(..), MoneyTotal, SortDirection(..), SortField(..), descriptionDisplay, expensesFor, summarizeMoney)
import Html exposing (Html, button, div, input, label, p, section, table, tbody, td, text, th, thead, tr)
import Html.Attributes exposing (attribute, class, type_, value)
import Html.Events exposing (onClick, onInput)
import Util.Date exposing (DateDisplay(..), formatDate)
import Util.Format exposing (formatMoney)


type alias Config msg =
    { expenses : List Expense
    , accounts : List Account
    , filterWindow : FilterWindow
    , dateDisplay : DateDisplay
    , customStart : String
    , customEnd : String
    , sortField : SortField
    , sortDirection : SortDirection
    , onSelectFilter : FilterWindow -> msg
    , onCustomStart : String -> msg
    , onCustomEnd : String -> msg
    , onSelectDateDisplay : DateDisplay -> msg
    , onSelectSort : SortField -> msg
    , onExportCsv : msg
    , onExportXlsx : msg
    }


view : Config msg -> Html msg
view config =
    section [ class "panel" ]
        [ Html.h2 [ class "section-title" ] [ text "Gastos" ]
        , tableControls config
        , if List.isEmpty config.expenses then
            p [ class "empty" ] [ text "Todavía no hay gastos." ]

          else
            div [ class "table-wrap" ]
                [ table [ class "expense-table" ]
                    [ thead []
                        [ tr []
                            [ sortableHeader config SortByDate "" "Fecha"
                            , sortableHeader config SortByAccount "" "Caja"
                            , sortableHeader config SortByDescription "" "Descripción"
                            , th [ class "numeric" ] [ text "Ingresado" ]
                            , sortableHeader config SortByExchangeRate "numeric" "Cotización"
                            , sortableHeader config SortByPesos "numeric" "Pesos"
                            , th [ class "equivalence" ] [ text "=" ]
                            , sortableHeader config SortByDollars "numeric" "Dólar"
                            ]
                        ]
                    , tbody [] (List.map (expenseRow config.dateDisplay) config.expenses ++ subtotalRows config.accounts config.expenses)
                    ]
                ]
        ]


tableControls : Config msg -> Html msg
tableControls config =
    div [ class "table-controls" ]
        [ filterControls config
        , exportControls config
        ]


filterControls : Config msg -> Html msg
filterControls config =
    div [ class "filters" ]
        [ div [ class "filter-buttons" ]
            [ filterButton config AllTime "Completo"
            , filterButton config ThisYear "Año"
            , filterButton config ThisMonth "Mes"
            , filterButton config ThisWeek "Semana"
            , filterButton config Today "Día"
            , filterButton config Custom "Personalizado"
            ]
        , div [ class "date-mode" ]
            [ p [] [ text "Fecha" ]
            , div [ class "filter-buttons" ]
                [ dateDisplayButton config NumericDate "DD/MM/AAAA"
                , dateDisplayButton config LongDate "Texto"
                ]
            ]
        , if config.filterWindow == Custom then
            div [ class "custom-range" ]
                [ label []
                    [ text "Desde"
                    , input [ type_ "date", value config.customStart, onInput config.onCustomStart ] []
                    ]
                , label []
                    [ text "Hasta"
                    , input [ type_ "date", value config.customEnd, onInput config.onCustomEnd ] []
                    ]
                ]

          else
            text ""
        ]


exportControls : Config msg -> Html msg
exportControls config =
    div [ class "export-controls" ]
        [ p [] [ text "Exportar" ]
        , div [ class "filter-buttons" ]
            [ button [ type_ "button", class "filter-button", onClick config.onExportCsv ] [ text "CSV" ]
            , button [ type_ "button", class "filter-button", onClick config.onExportXlsx ] [ text "XLSX" ]
            ]
        ]


filterButton : Config msg -> FilterWindow -> String -> Html msg
filterButton config filterWindow labelText =
    button
        [ type_ "button"
        , class
            (if config.filterWindow == filterWindow then
                "filter-button filter-button--active"

             else
                "filter-button"
            )
        , onClick (config.onSelectFilter filterWindow)
        ]
        [ text labelText ]


dateDisplayButton : Config msg -> DateDisplay -> String -> Html msg
dateDisplayButton config dateDisplay labelText =
    button
        [ type_ "button"
        , class
            (if config.dateDisplay == dateDisplay then
                "filter-button filter-button--active"

             else
                "filter-button"
            )
        , onClick (config.onSelectDateDisplay dateDisplay)
        ]
        [ text labelText ]


expenseRow : DateDisplay -> Expense -> Html msg
expenseRow dateDisplay expense =
    tr []
        [ td [ attribute "data-label" "Fecha" ] [ text (formatDate dateDisplay expense.date) ]
        , td [ attribute "data-label" "Caja" ] [ text expense.accountName ]
        , td [ attribute "data-label" "Descripción" ] [ text (descriptionDisplay expense) ]
        , td [ attribute "data-label" "Ingresado", class "numeric" ] [ text (formatMoney expense.inputCurrency expense.inputAmount) ]
        , td [ attribute "data-label" "Cotización", class "numeric" ] [ text (formatMoney ARS expense.exchangeRate) ]
        , td [ attribute "data-label" "Pesos", class "numeric" ] [ text (formatMoney ARS expense.ars) ]
        , td [ class "equivalence" ] [ text "=" ]
        , td [ attribute "data-label" "Dólar", class "numeric" ] [ text (formatMoney USD expense.usd) ]
        ]


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


subtotalRows : List Account -> List Expense -> List (Html msg)
subtotalRows accounts expenses =
    let
        grandTotal =
            summarizeMoney expenses
    in
    List.map (\account -> totalRow ("Subtotal " ++ account.name) "subtotal" (summarizeMoney (expensesFor account expenses))) accounts
        ++ [ totalRow "Total" "grand-total" grandTotal ]


totalRow : String -> String -> MoneyTotal -> Html msg
totalRow labelText rowClass total =
    tr [ class rowClass ]
        [ td [ attribute "colspan" "5", attribute "data-label" "Total" ] [ text labelText ]
        , td [ attribute "data-label" "Pesos", class "numeric" ] [ text (formatMoney ARS total.ars) ]
        , td [ class "equivalence" ] [ text "=" ]
        , td [ attribute "data-label" "Dólar", class "numeric" ] [ text (formatMoney USD total.usd) ]
        ]
