module Workspace exposing
    ( LoadState(..)
    , Member
    , WorkspaceSummary
    , decodeWorkspace
    , encodeExpense
    , encodeGuestInvite
    , encodeGuestRemove
    , encodeUserCreate
    , encodeUserDelete
    , encodeWorkspaceName
    , encodeWorkspaceRequest
    )

import Accounting exposing (Expense, WorkspaceUser, currencyFromString, currencyToString)
import Json.Decode as Decode
import Json.Encode as Encode


type LoadState
    = NotLoaded
    | Loading
    | Loaded
    | LoadError String


type alias WorkspaceSummary =
    { id : String
    , name : String
    , ownerUid : String
    , members : List Member
    }


type alias Member =
    { uid : String
    , email : String
    , displayName : String
    }


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


encodeUserCreate : String -> String -> Encode.Value
encodeUserCreate workspaceId name =
    Encode.object
        [ ( "workspaceId", Encode.string workspaceId )
        , ( "name", Encode.string name )
        ]


encodeUserDelete : String -> String -> Encode.Value
encodeUserDelete workspaceId userId =
    Encode.object
        [ ( "workspaceId", Encode.string workspaceId )
        , ( "userId", Encode.string userId )
        ]


encodeGuestInvite : String -> String -> Encode.Value
encodeGuestInvite workspaceId email =
    Encode.object
        [ ( "workspaceId", Encode.string workspaceId )
        , ( "email", Encode.string email )
        ]


encodeGuestRemove : String -> String -> Encode.Value
encodeGuestRemove workspaceId uid =
    Encode.object
        [ ( "workspaceId", Encode.string workspaceId )
        , ( "uid", Encode.string uid )
        ]


encodeWorkspaceName : String -> String -> Encode.Value
encodeWorkspaceName workspaceId name =
    Encode.object
        [ ( "workspaceId", Encode.string workspaceId )
        , ( "name", Encode.string name )
        ]


encodeExpenseRecord : Expense -> Encode.Value
encodeExpenseRecord expense =
    Encode.object
        [ ( "id", Encode.string expense.id )
        , ( "description", Encode.string expense.description )
        , ( "userId", Encode.string expense.userId )
        , ( "userName", Encode.string expense.userName )
        , ( "inputAmount", Encode.float expense.inputAmount )
        , ( "inputCurrency", Encode.string (currencyToString expense.inputCurrency) )
        , ( "exchangeRate", Encode.float expense.exchangeRate )
        , ( "ars", Encode.float expense.ars )
        , ( "usd", Encode.float expense.usd )
        , ( "date", Encode.string expense.date )
        ]


decodeWorkspace : Decode.Value -> Result String { expenses : List Expense, users : List WorkspaceUser, workspaces : List WorkspaceSummary, currentWorkspaceId : String }
decodeWorkspace value =
    Decode.decodeValue workspacePayloadDecoder value
        |> Result.mapError Decode.errorToString


workspacePayloadDecoder : Decode.Decoder { expenses : List Expense, users : List WorkspaceUser, workspaces : List WorkspaceSummary, currentWorkspaceId : String }
workspacePayloadDecoder =
    Decode.field "status" Decode.string
        |> Decode.andThen
            (\status ->
                case status of
                    "loaded" ->
                        Decode.map4
                            (\workspaces currentWorkspaceId users expenses ->
                                { workspaces = workspaces
                                , currentWorkspaceId = currentWorkspaceId
                                , users = users
                                , expenses = expenses
                                }
                            )
                            (Decode.field "workspaces" (Decode.list workspaceSummaryDecoder))
                            (Decode.field "workspaceId" Decode.string)
                            (Decode.field "users" (Decode.list userDecoder))
                            (Decode.field "expenses" (Decode.list expenseDecoder))

                    "error" ->
                        Decode.field "message" Decode.string
                            |> Decode.andThen Decode.fail

                    _ ->
                        Decode.fail ("Estado de workspace desconocido: " ++ status)
            )


userDecoder : Decode.Decoder WorkspaceUser
userDecoder =
    Decode.map3 WorkspaceUser
        (Decode.field "id" Decode.string)
        (Decode.field "name" Decode.string)
        (Decode.maybe (Decode.field "deletedAt" Decode.string))


workspaceSummaryDecoder : Decode.Decoder WorkspaceSummary
workspaceSummaryDecoder =
    Decode.map4 WorkspaceSummary
        (Decode.field "id" Decode.string)
        (Decode.field "name" Decode.string)
        (Decode.field "ownerUid" Decode.string)
        (Decode.field "members" (Decode.list memberDecoder))


memberDecoder : Decode.Decoder Member
memberDecoder =
    Decode.map3 Member
        (Decode.field "uid" Decode.string)
        (Decode.field "email" Decode.string)
        (Decode.field "displayName" Decode.string)


expenseDecoder : Decode.Decoder Expense
expenseDecoder =
    Decode.map8
        (\id description userId userName inputAmount inputCurrency exchangeRate ars ->
            \usd date deletedAt ->
                { id = id
                , description = description
                , userId = userId
                , userName = userName
                , inputAmount = inputAmount
                , inputCurrency = inputCurrency
                , exchangeRate = exchangeRate
                , ars = ars
                , usd = usd
                , date = date
                , deletedAt = deletedAt
                }
        )
        (Decode.field "id" Decode.string)
        (Decode.field "description" Decode.string)
        (Decode.field "userId" Decode.string)
        (Decode.field "userName" Decode.string)
        (Decode.field "inputAmount" Decode.float)
        (Decode.field "inputCurrency" (Decode.map currencyFromString Decode.string))
        (Decode.field "exchangeRate" Decode.float)
        (Decode.field "ars" Decode.float)
        |> Decode.andThen
            (\buildExpense ->
                Decode.map3 buildExpense
                    (Decode.field "usd" Decode.float)
                    (Decode.field "date" Decode.string)
                    (Decode.maybe (Decode.field "deletedAt" Decode.string))
            )
