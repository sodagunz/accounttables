module Export exposing (Format(..), tablePayload)

import Accounting exposing (Account, Currency(..), Expense, MoneyTotal, expensesFor, summarizeMoney)
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


tablePayload : Format -> DateDisplay -> String -> List Account -> List Expense -> Encode.Value
tablePayload format dateDisplay today accounts expenses =
    Encode.object
        [ ( "format", Encode.string (formatToString format) )
        , ( "filename", Encode.string (filename format today) )
        , ( "sheetName", Encode.string "Gastos" )
        , ( "headers", Encode.list Encode.string headers )
        , ( "rows", Encode.list rowEncoder (expenseRows dateDisplay expenses ++ subtotalRows accounts expenses) )
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
    , "Caja"
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
        , expense.accountName
        , expense.description
        , formatMoney expense.inputCurrency expense.inputAmount
        , formatMoney ARS expense.exchangeRate
        , formatMoney ARS expense.ars
        , "="
        , formatMoney USD expense.usd
        ]
    }


subtotalRows : List Account -> List Expense -> List TableRow
subtotalRows accounts expenses =
    let
        grandTotal =
            summarizeMoney expenses
    in
    List.map (\account -> totalRow ("Subtotal " ++ account.name) "subtotal" (summarizeMoney (expensesFor account expenses))) accounts
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
