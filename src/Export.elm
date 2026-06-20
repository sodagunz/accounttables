module Export exposing (Format(..), tablePayload)

import Accounting exposing (Account, Currency(..), Movement, MoneyTotal, descriptionDisplay, movementsFor, summarizeMoney)
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


rowEncoder : TableRow -> Encode.Value
rowEncoder row =
    Encode.object
        [ ( "type", Encode.string row.label )
        , ( "cells", Encode.list Encode.string row.cells )
        ]
