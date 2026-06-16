module UpdateTest exposing (suite)

import Accounting
import Auth exposing (AuthState(..))
import Expect
import Json.Decode as Decode
import Json.Encode as Encode
import Ledger exposing (LoadState(..))
import Model exposing (StorageMode(..))
import Test exposing (Test, describe, test)
import Update.Accounts as Accounts
import Update.Ledgers as Ledgers


suite : Test
suite =
    describe "Update helpers"
        [ describe "accounts"
            [ test "adds a local account with trimmed name" <|
                \_ ->
                    let
                        ( updatedModel, payload ) =
                            Accounts.add
                                { initialModel
                                    | authState = SignedOut
                                    , storageMode = LocalOnly
                                    , currentLedgerId = "local"
                                    , newAccountName = "  Caja  "
                                }
                    in
                    Expect.all
                        [ \_ -> Expect.equal "" updatedModel.newAccountName
                        , \_ -> Expect.equal "" updatedModel.accountError
                        , \_ -> expectEncodedString "ledgerId" "local" payload
                        , \_ -> expectEncodedString "name" "Caja" payload
                        ]
                        ()
            , test "requires sign-in when cloud synced without an auth user" <|
                \_ ->
                    let
                        ( updatedModel, payload ) =
                            Accounts.add
                                { initialModel
                                    | authState = SignedOut
                                    , storageMode = CloudSynced
                                    , currentLedgerId = "ledger-1"
                                    , newAccountName = "Caja"
                                }
                    in
                    Expect.all
                        [ \_ -> Expect.equal Nothing payload
                        , \_ -> Expect.equal "Ingresa con Google para guardar cuentas en el libro contable." updatedModel.accountError
                        ]
                        ()
            ]
        , describe "ledgers"
            [ test "select clears loaded data and marks the ledger loading" <|
                \_ ->
                    let
                        selected =
                            Ledgers.select "ledger-2"
                                { initialModel
                                    | ledgers =
                                        [ { id = "ledger-2", name = "Trabajo", ownerUid = "owner", members = [], invitedEmails = [] } ]
                                    , expenses = [ sampleExpense ]
                                    , accounts = [ sampleAccount ]
                                    , error = "old"
                                    , accountError = "old"
                                    , ledgerError = "old"
                                }
                    in
                    Expect.all
                        [ \model -> Expect.equal "ledger-2" model.currentLedgerId
                        , \model -> Expect.equal "Trabajo" model.ledgerName
                        , \model -> Expect.equal Loading model.ledgerLoadState
                        , \model -> Expect.equal [] model.expenses
                        , \model -> Expect.equal [] model.accounts
                        , \model -> Expect.equal "" model.ledgerError
                        ]
                        selected
            , test "invites collaborators with normalized email" <|
                \_ ->
                    let
                        ( updatedModel, payload ) =
                            Ledgers.inviteGuest
                                { initialModel
                                    | storageMode = CloudSynced
                                    , currentLedgerId = "ledger-1"
                                    , inviteEmail = "  USER@Example.COM  "
                                }
                    in
                    Expect.all
                        [ \_ -> Expect.equal "" updatedModel.inviteEmail
                        , \_ -> Expect.equal "" updatedModel.ledgerError
                        , \_ -> expectEncodedString "ledgerId" "ledger-1" payload
                        , \_ -> expectEncodedString "email" "user@example.com" payload
                        ]
                        ()
            ]
        , test "ensureSelectedAccount ignores deleted accounts" <|
            \_ ->
                let
                    updatedModel =
                        Model.ensureSelectedAccount
                            { initialModel
                                | accounts =
                                    [ { id = "deleted", name = "Vieja", deletedAt = Just "deleted" }
                                    , { id = "active", name = "Caja", deletedAt = Nothing }
                                    ]
                                , form = { modelForm | accountId = "deleted" }
                            }
                in
                Expect.equal "active" updatedModel.form.accountId
        , test "ensureLocalLedger activates the browser-local ledger" <|
            \_ ->
                let
                    updatedModel =
                        Ledger.ensureLocalLedger LocalOnly
                            { initialModel
                                | currentLedgerId = ""
                                , storageMode = CloudSynced
                                , ledgerLoadState = Loading
                            }
                in
                Expect.all
                    [ \model -> Expect.equal Ledger.localLedgerId model.currentLedgerId
                    , \model -> Expect.equal Ledger.localLedgerName model.ledgerName
                    , \model -> Expect.equal LocalOnly model.storageMode
                    , \model -> Expect.equal Loaded model.ledgerLoadState
                    ]
                    updatedModel
        ]


expectEncodedString : String -> String -> Maybe Encode.Value -> Expect.Expectation
expectEncodedString field expected maybePayload =
    case maybePayload of
        Just payload ->
            Decode.decodeValue (Decode.field field Decode.string) payload
                |> Expect.equal (Ok expected)

        Nothing ->
            Expect.fail ("Expected payload with field " ++ field)


initialModel =
    Model.initial


modelForm =
    Model.initial.form


sampleAccount =
    { id = "cash", name = "Caja", deletedAt = Nothing }


sampleExpense =
    { id = "movement-1"
    , movementType = Accounting.ExpenseMovement
    , description = Just "Pago"
    , accountId = "cash"
    , accountName = "Caja"
    , inputAmount = 1
    , inputCurrency = Accounting.ARS
    , exchangeRate = 1000
    , ars = -1
    , usd = -0.001
    , date = "2026-06-16"
    , deletedAt = Nothing
    }
