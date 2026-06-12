module Export exposing (Format(..), tablePayload)

import Accounting exposing (Currency(..), Expense, MoneyTotal, Person(..), expensesFor, personToString, summarizeMoney)
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


tablePayload : Format -> DateDisplay -> String -> List Expense -> Encode.Value
tablePayload format dateDisplay today expenses =
    Encode.object
        [ ( "format", Encode.string (formatToString format) )
        , ( "filename", Encode.string (filename format today) )
        , ( "sheetName", Encode.string "Gastos" )
        , ( "headers", Encode.list Encode.string headers )
        , ( "rows", Encode.list rowEncoder (expenseRows dateDisplay expenses ++ subtotalRows expenses) )
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
    "contabilizar-gastos-"
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
    , "Nombre"
    , "Descripción"
    , "Ingresado"
    , "Cotización"
    , "Pesos"
    , "="
    , "Dólar"
    ]


expenseRows : DateDisplay -> List Expense -> List TableRow
expenseRows dateDisplay expenses =
    List.map (expenseRow dateDisplay) expenses


expenseRow : DateDisplay -> Expense -> TableRow
expenseRow dateDisplay expense =
    { label = "expense"
    , cells =
        [ formatDate dateDisplay expense.date
        , personToString expense.person
        , expense.description
        , formatMoney expense.inputCurrency expense.inputAmount
        , formatMoney ARS expense.exchangeRate
        , formatMoney ARS expense.ars
        , "="
        , formatMoney USD expense.usd
        ]
    }


subtotalRows : List Expense -> List TableRow
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
    , totalRow "Total" "total" grandTotal
    ]


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
        , "="
        , formatMoney USD total.usd
        ]
    }


rowEncoder : TableRow -> Encode.Value
rowEncoder row =
    Encode.object
        [ ( "type", Encode.string row.label )
        , ( "cells", Encode.list Encode.string row.cells )
        ]
