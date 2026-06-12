module View.ExpenseTable exposing (Config, view)

import Accounting exposing (Currency(..), Expense, FilterWindow(..), MoneyTotal, Person(..), SortDirection(..), SortField(..), expensesFor, personToString, summarizeMoney)
import Html exposing (Html, button, div, input, label, p, section, table, tbody, td, text, th, thead, tr)
import Html.Attributes exposing (attribute, class, type_, value)
import Html.Events exposing (onClick, onInput)
import Util.Date exposing (DateDisplay(..), formatDate)
import Util.Format exposing (formatMoney)


type alias Config msg =
    { expenses : List Expense
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
    }


view : Config msg -> Html msg
view config =
    section [ class "panel" ]
        [ Html.h2 [ class "section-title" ] [ text "Gastos" ]
        , filterControls config
        , if List.isEmpty config.expenses then
            p [ class "empty" ] [ text "Todavía no hay gastos." ]

          else
            div [ class "table-wrap" ]
                [ table []
                    [ thead []
                        [ tr []
                            [ sortableHeader config SortByDate "" "Fecha"
                            , sortableHeader config SortByPerson "" "Nombre"
                            , sortableHeader config SortByDescription "" "Descripción"
                            , th [ class "numeric" ] [ text "Ingresado" ]
                            , sortableHeader config SortByExchangeRate "numeric" "Cotización"
                            , sortableHeader config SortByPesos "numeric" "Pesos"
                            , th [ class "equivalence" ] [ text "=" ]
                            , sortableHeader config SortByDollars "numeric" "Dólar"
                            ]
                        ]
                    , tbody [] (List.map (expenseRow config.dateDisplay) config.expenses ++ subtotalRows config.expenses)
                    ]
                ]
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
        [ td [] [ text (formatDate dateDisplay expense.date) ]
        , td [] [ text (personToString expense.person) ]
        , td [] [ text expense.description ]
        , td [ class "numeric" ] [ text (formatMoney expense.inputCurrency expense.inputAmount) ]
        , td [ class "numeric" ] [ text (formatMoney ARS expense.exchangeRate) ]
        , td [ class "numeric" ] [ text (formatMoney ARS expense.ars) ]
        , td [ class "equivalence" ] [ text "=" ]
        , td [ class "numeric" ] [ text (formatMoney USD expense.usd) ]
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


subtotalRows : List Expense -> List (Html msg)
subtotalRows expenses =
    let
        aliceTotal =
            summarizeMoney (expensesFor Alice expenses)

        bobTotal =
            summarizeMoney (expensesFor Bob expenses)

        grandTotal =
            summarizeMoney expenses
    in
    [ totalRow "Subtotal Alice" "subtotal" aliceTotal
    , totalRow "Subtotal Bob" "subtotal" bobTotal
    , totalRow "Total" "grand-total" grandTotal
    ]


totalRow : String -> String -> MoneyTotal -> Html msg
totalRow labelText rowClass total =
    tr [ class rowClass ]
        [ td [ attribute "colspan" "5" ] [ text labelText ]
        , td [ class "numeric" ] [ text (formatMoney ARS total.ars) ]
        , td [ class "equivalence" ] [ text "=" ]
        , td [ class "numeric" ] [ text (formatMoney USD total.usd) ]
        ]
