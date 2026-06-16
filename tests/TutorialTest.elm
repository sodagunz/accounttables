module TutorialTest exposing (suite)

import Auth exposing (AuthState(..))
import Expect
import Json.Decode as Decode
import Model exposing (TutorialStep(..))
import Test exposing (Test, describe, test)
import Tutorial


suite : Test
suite =
    describe "Tutorial"
        [ test "reopens at accounts when no account exists" <|
            \_ ->
                Tutorial.reopenedStep initialModel
                    |> Expect.equal AccountsStep
        , test "reopens at first expense after account setup when signed out" <|
            \_ ->
                Tutorial.reopenedStep { initialModel | accounts = [ activeAccount ] }
                    |> Expect.equal FirstExpenseStep
        , test "reopens at collaborators after account setup when signed in" <|
            \_ ->
                Tutorial.reopenedStep
                    { initialModel
                        | accounts = [ activeAccount ]
                        , authState =
                            SignedIn
                                { uid = "user-1"
                                , displayName = "Ana"
                                , email = "ana@example.com"
                                , photoUrl = ""
                                , acceptedInviteLedgerId = Nothing
                                }
                    }
                    |> Expect.equal CollaboratorsStep
        , test "prefills first expense with demo income and selected account" <|
            \_ ->
                let
                    form =
                        initialModel.form

                    prepared =
                        Tutorial.prepareStep FirstExpenseStep
                            { initialModel
                                | accounts = [ activeAccount ]
                                , form = { form | accountId = "" }
                            }
                in
                Expect.all
                    [ \model -> Expect.equal "1000" model.form.amount
                    , \model -> Expect.equal "Venta de prueba" model.form.description
                    , \model -> Expect.equal "cash" model.form.accountId
                    , \model -> Expect.equal Nothing model.form.editingId
                    ]
                    prepared
        , test "encodes delete selector for the tutorial-created expense" <|
            \_ ->
                Tutorial.encodeStep { initialModel | tutorialExpenseId = Just "movement-1" } DeleteExpenseStep
                    |> Decode.decodeValue (Decode.field "selector" Decode.string)
                    |> Expect.equal (Ok "[data-tutorial=\"delete-movement-1\"]")
        ]


initialModel =
    Model.initial


activeAccount =
    { id = "cash", name = "Caja", deletedAt = Nothing }
