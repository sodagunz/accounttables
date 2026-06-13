module Workspace exposing
    ( LoadState(..)
    , decodeExpenses
    , encodeExpense
    , encodeWorkspaceRequest
    , workspaceIdForUser
    )

import Accounting exposing (Expense, currencyFromString, currencyToString, personFromString, personToString)
import Auth
import Json.Decode as Decode
import Json.Encode as Encode


type LoadState
    = NotLoaded
    | Loading
    | Loaded
    | LoadError String


workspaceIdForUser : Auth.User -> String
workspaceIdForUser user =
    user.uid


encodeWorkspaceRequest : String -> Encode.Value
encodeWorkspaceRequest workspaceId =
    Encode.object
        [ ( "workspaceId", Encode.string workspaceId ) ]


encodeExpense : String -> Expense -> Encode.Value
encodeExpense workspaceId expense =
    Encode.object
        [ ( "workspaceId", Encode.string workspaceId )
        , ( "expense", encodeExpenseRecord expense )
        ]


encodeExpenseRecord : Expense -> Encode.Value
encodeExpenseRecord expense =
    Encode.object
        [ ( "id", Encode.int expense.id )
        , ( "description", Encode.string expense.description )
        , ( "person", Encode.string (personToString expense.person) )
        , ( "inputAmount", Encode.float expense.inputAmount )
        , ( "inputCurrency", Encode.string (currencyToString expense.inputCurrency) )
        , ( "exchangeRate", Encode.float expense.exchangeRate )
        , ( "ars", Encode.float expense.ars )
        , ( "usd", Encode.float expense.usd )
        , ( "date", Encode.string expense.date )
        ]


decodeExpenses : Decode.Value -> Result String (List Expense)
decodeExpenses value =
    Decode.decodeValue expensesPayloadDecoder value
        |> Result.mapError Decode.errorToString


expensesPayloadDecoder : Decode.Decoder (List Expense)
expensesPayloadDecoder =
    Decode.field "status" Decode.string
        |> Decode.andThen
            (\status ->
                case status of
                    "loaded" ->
                        Decode.field "expenses" (Decode.list expenseDecoder)

                    "error" ->
                        Decode.field "message" Decode.string
                            |> Decode.andThen Decode.fail

                    _ ->
                        Decode.fail ("Estado de workspace desconocido: " ++ status)
            )


expenseDecoder : Decode.Decoder Expense
expenseDecoder =
    Decode.map8
        (\id description person inputAmount inputCurrency exchangeRate ars usd ->
            \date ->
                { id = id
                , description = description
                , person = person
                , inputAmount = inputAmount
                , inputCurrency = inputCurrency
                , exchangeRate = exchangeRate
                , ars = ars
                , usd = usd
                , date = date
                }
        )
        (Decode.field "id" Decode.int)
        (Decode.field "description" Decode.string)
        (Decode.field "person" (Decode.map personFromString Decode.string))
        (Decode.field "inputAmount" Decode.float)
        (Decode.field "inputCurrency" (Decode.map currencyFromString Decode.string))
        (Decode.field "exchangeRate" Decode.float)
        (Decode.field "ars" Decode.float)
        (Decode.field "usd" Decode.float)
        |> Decode.andThen
            (\buildExpense ->
                Decode.field "date" Decode.string
                    |> Decode.map buildExpense
            )
