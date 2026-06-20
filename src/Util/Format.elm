module Util.Format exposing (formatMoney, formatNumber)

import Accounting exposing (Currency(..))
import Util.Date exposing (pad2)


formatMoney : Currency -> Float -> String
formatMoney currency amount =
    let
        prefix : String
        prefix =
            case currency of
                ARS ->
                    "ARS "

                USD ->
                    "U$D "

        formatted : String
        formatted =
            prefix ++ formatFloat (abs amount)
    in
    if amount < 0 then
        "(" ++ formatted ++ ")"

    else
        formatted


formatNumber : Float -> String
formatNumber amount =
    let
        formatted : String
        formatted =
            formatFloat (abs amount)
    in
    if amount < 0 then
        "(" ++ formatted ++ ")"

    else
        formatted


formatFloat : Float -> String
formatFloat amount =
    let
        cents : Int
        cents =
            round (abs amount * 100)

        whole : Int
        whole =
            cents // 100

        decimal : Int
        decimal =
            modBy 100 cents
    in
    formatThousands whole ++ "," ++ pad2 decimal


formatThousands : Int -> String
formatThousands number =
    let
        absolute : Int
        absolute =
            abs number

        formatted : String
        formatted =
            formatPositiveThousands absolute
    in
    if number < 0 then
        "-" ++ formatted

    else
        formatted


formatPositiveThousands : Int -> String
formatPositiveThousands number =
    if number < 1000 then
        String.fromInt number

    else
        formatPositiveThousands (number // 1000) ++ "." ++ pad3 (modBy 1000 number)


pad3 : Int -> String
pad3 number =
    if number < 10 then
        "00" ++ String.fromInt number

    else if number < 100 then
        "0" ++ String.fromInt number

    else
        String.fromInt number
