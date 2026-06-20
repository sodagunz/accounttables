module TutorialTest exposing (suite)

import Auth exposing (AuthState(..))
import Expect
import Json.Decode as Decode
import Json.Encode as Encode
import Model exposing (TutorialState(..), TutorialStep(..))
import Test exposing (Test, describe, test)
import Tutorial


suite : Test
suite =
    describe "Tutorial"
        [ test "reopens at accounts when no account exists" <|
            \_ ->
                Tutorial.reopenedStep initialModel
                    |> Expect.equal AccountsStep
        , test "decodes completed state from startup flags" <|
            \_ ->
                Encode.object [ ( "tutorialState", Encode.string "completed" ) ]
                    |> Tutorial.decodeTutorialStateFromFlags
                    |> Expect.equal TutorialCompleted
        , test "reopens at first expense after account setup when signed out" <|
            \_ ->
                Tutorial.reopenedStep { initialModel | accounts = [ activeAccount ] }
                    |> Expect.equal FirstMovementStep
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
                        Tutorial.prepareStep FirstMovementStep
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
                Tutorial.encodeStep { initialModel | tutorialMovementId = Just "movement-1" } DeleteMovementStep
                    |> Decode.decodeValue (Decode.field "selector" Decode.string)
                    |> Expect.equal (Ok "[data-tutorial=\"delete-movement-1\"]")
        ]


initialModel =
    Model.initial


activeAccount =
    { id = "cash", name = "Caja", deletedAt = Nothing }
