module Tutorial exposing
    ( Config
    , decodeTutorialStateFromFlags
    , encodeStep
    , handleTutorialAction
    , prepareState
    , prepareStep
    , reopenedStep
    , stepAfterAccounts
    , tutorialAdvanceCmd
    , tutorialNavigateCmd
    , tutorialNavigateTo
    )

import Accounting
import Auth exposing (AuthState(..))
import Json.Decode as Decode
import Json.Encode as Encode
import Model exposing (Model, TutorialState(..), TutorialStep(..))


type alias Config msg =
    { showStep : Encode.Value -> Cmd msg
    , openDisclosure : String -> Cmd msg
    , focusElement : String -> Cmd msg
    , hide : () -> Cmd msg
    , saveState : Encode.Value -> Cmd msg
    }


decodeTutorialStateFromFlags : Decode.Value -> TutorialState
decodeTutorialStateFromFlags flags =
    case Decode.decodeValue (Decode.field "tutorialState" Decode.string) flags of
        Ok "dismissed" ->
            TutorialDismissed

        Ok "completed" ->
            TutorialCompleted

        _ ->
            TutorialOpen SignInStep


actionDecoder : Decode.Decoder String
actionDecoder =
    Decode.field "action" Decode.string


handleTutorialAction : Config msg -> Decode.Value -> Model -> ( Model, Cmd msg )
handleTutorialAction config value model =
    case Decode.decodeValue actionDecoder value of
        Ok "next" ->
            case model.tutorialState of
                TutorialOpen step ->
                    advanceTutorialFrom config step model

                _ ->
                    ( model, Cmd.none )

        Ok "back" ->
            case model.tutorialState of
                TutorialOpen step ->
                    tutorialNavigateTo config (previousStep step) model

                _ ->
                    ( model, Cmd.none )

        Ok "skip" ->
            case model.tutorialState of
                TutorialOpen step ->
                    skipTutorialFrom config step model

                _ ->
                    ( model, Cmd.none )

        Ok "done" ->
            completeTutorial config model

        Ok "target-missing" ->
            ( model, Cmd.none )

        _ ->
            ( model, Cmd.none )


advanceTutorialFrom : Config msg -> TutorialStep -> Model -> ( Model, Cmd msg )
advanceTutorialFrom config step model =
    case step of
        AccountsStep ->
            tutorialNavigateTo config (stepAfterAccounts model) model

        _ ->
            case nextStep step of
                Just next ->
                    tutorialNavigateTo config next model

                Nothing ->
                    completeTutorial config model


skipTutorialFrom : Config msg -> TutorialStep -> Model -> ( Model, Cmd msg )
skipTutorialFrom config step model =
    case step of
        SignInStep ->
            if List.isEmpty (Model.activeAccounts model) then
                tutorialNavigateTo config AccountsStep model

            else
                tutorialNavigateTo config (stepAfterAccounts model) model

        CollaboratorsStep ->
            tutorialNavigateTo config FirstMovementStep model

        FirstMovementStep ->
            completeTutorial config model

        AccountsStep ->
            ( model, Cmd.none )

        DeleteMovementStep ->
            ( model, Cmd.none )


tutorialAdvanceCmd : Config msg -> Model -> TutorialState -> TutorialState -> Cmd msg
tutorialAdvanceCmd config model oldState newState =
    case ( oldState, newState ) of
        ( TutorialOpen SignInStep, TutorialOpen step ) ->
            tutorialNavigateCmd config model step

        _ ->
            Cmd.none


tutorialNavigateCmd : Config msg -> Model -> TutorialStep -> Cmd msg
tutorialNavigateCmd config model step =
    Cmd.batch
        [ tutorialOpenDisclosureCmd config step
        , config.showStep (encodeStep model step)
        , config.focusElement (focusSelector model step)
        ]


tutorialNavigateTo : Config msg -> TutorialStep -> Model -> ( Model, Cmd msg )
tutorialNavigateTo config step model =
    let
        preparedModel : Model
        preparedModel =
            prepareStep step { model | tutorialState = TutorialOpen step }
    in
    ( preparedModel
    , tutorialNavigateCmd config preparedModel step
    )


tutorialOpenDisclosureCmd : Config msg -> TutorialStep -> Cmd msg
tutorialOpenDisclosureCmd config step =
    openDisclosureIds step
        |> List.map config.openDisclosure
        |> Cmd.batch


completeTutorial : Config msg -> Model -> ( Model, Cmd msg )
completeTutorial config model =
    ( { model | tutorialState = TutorialCompleted, tutorialCompletionVisible = True, tutorialMovementId = Nothing }
    , Cmd.batch
        [ config.hide ()
        , config.saveState (Encode.string "completed")
        ]
    )


encodeStep : Model -> TutorialStep -> Encode.Value
encodeStep model step =
    Encode.object
        [ ( "step", Encode.string (stepName step) )
        , ( "selector", Encode.string (targetSelector model step) )
        , ( "title", Encode.string "" )
        , ( "description", Encode.string (stepText step) )
        , ( "side", Encode.string (stepSide step) )
        , ( "align", Encode.string "start" )
        , ( "showBack", Encode.bool (showBack step) )
        , ( "showNext", Encode.bool (showNext step) )
        , ( "showSkip", Encode.bool (showSkip step) )
        , ( "done", Encode.bool doneButton )
        , ( "allowTargetClick", Encode.bool (allowsTargetClick step) )
        , ( "openDisclosures", Encode.list Encode.string (openDisclosureIds step) )
        ]


targetSelector : Model -> TutorialStep -> String
targetSelector model step =
    case step of
        SignInStep ->
            "[data-tutorial=\"sign-in\"]"

        AccountsStep ->
            "[data-tutorial=\"account-form\"]"

        CollaboratorsStep ->
            "[data-tutorial=\"invite-email\"]"

        FirstMovementStep ->
            "[data-tutorial=\"movement-form\"]"

        DeleteMovementStep ->
            case model.tutorialMovementId of
                Just expenseId ->
                    "[data-tutorial=\"delete-" ++ expenseId ++ "\"]"

                Nothing ->
                    "[data-tutorial=\"movement-form\"]"


focusSelector : Model -> TutorialStep -> String
focusSelector model step =
    case step of
        FirstMovementStep ->
            "[data-tutorial=\"movement-amount\"]"

        _ ->
            targetSelector model step


prepareState : Model -> Model
prepareState model =
    case model.tutorialState of
        TutorialOpen step ->
            prepareStep step model

        _ ->
            model


prepareStep : TutorialStep -> Model -> Model
prepareStep step model =
    case step of
        FirstMovementStep ->
            prefillMovementForm model

        _ ->
            model


nextStep : TutorialStep -> Maybe TutorialStep
nextStep step =
    case step of
        SignInStep ->
            Just AccountsStep

        AccountsStep ->
            Just CollaboratorsStep

        CollaboratorsStep ->
            Just FirstMovementStep

        FirstMovementStep ->
            Just DeleteMovementStep

        DeleteMovementStep ->
            Nothing


previousStep : TutorialStep -> TutorialStep
previousStep step =
    case step of
        SignInStep ->
            SignInStep

        AccountsStep ->
            SignInStep

        CollaboratorsStep ->
            AccountsStep

        FirstMovementStep ->
            CollaboratorsStep

        DeleteMovementStep ->
            FirstMovementStep


reopenedStep : Model -> TutorialStep
reopenedStep model =
    if List.isEmpty (Model.activeAccounts model) then
        AccountsStep

    else
        stepAfterAccounts model


stepAfterAccounts : Model -> TutorialStep
stepAfterAccounts model =
    case model.authState of
        SignedIn _ ->
            CollaboratorsStep

        _ ->
            FirstMovementStep


openDisclosureIds : TutorialStep -> List String
openDisclosureIds step =
    case step of
        AccountsStep ->
            [ "admin-tool", "accounts-tool" ]

        CollaboratorsStep ->
            [ "admin-tool", "members-tool" ]

        _ ->
            []


prefillMovementForm : Model -> Model
prefillMovementForm model =
    let
        accountId : String
        accountId =
            case model.form.accountId of
                "" ->
                    Model.activeAccounts model
                        |> List.head
                        |> Maybe.map .id
                        |> Maybe.withDefault ""

                selectedAccountId ->
                    selectedAccountId

        form : Accounting.Form
        form =
            model.form
    in
    { model
        | form =
            { form
                | amount = "1000"
                , description = "Venta de prueba"
                , accountId = accountId
                , movementType = Accounting.IncomeMovement
                , relatedToInvoice = False
                , documentNumber = ""
                , allocationIntent = Nothing
                , editingId = Nothing
            }
    }


stepText : TutorialStep -> String
stepText step =
    case step of
        SignInStep ->
            "Para empezar, inicia sesion con Google. Si no quieres sincronizar, puedes saltar este paso."

        AccountsStep ->
            "Crea una cuenta para registrar movimientos. Dale un nombre y agregala."

        CollaboratorsStep ->
            "Invita a alguien por email para trabajar juntos. Tambien puedes hacerlo despues."

        FirstMovementStep ->
            "Registra tu primer movimiento. El importe y la descripcion ya estan completos. Presiona Guardar."

        DeleteMovementStep ->
            "Perfecto. Ahora borremos este movimiento de prueba para que todo quede limpio. Presiona el boton de eliminar."


stepName : TutorialStep -> String
stepName step =
    case step of
        SignInStep ->
            "sign-in"

        AccountsStep ->
            "accounts"

        CollaboratorsStep ->
            "collaborators"

        FirstMovementStep ->
            "first-expense"

        DeleteMovementStep ->
            "delete-expense"


stepSide : TutorialStep -> String
stepSide step =
    case step of
        SignInStep ->
            "bottom"

        AccountsStep ->
            "right"

        CollaboratorsStep ->
            "right"

        FirstMovementStep ->
            "right"

        DeleteMovementStep ->
            "left"


showBack : TutorialStep -> Bool
showBack step =
    step /= SignInStep


showNext : TutorialStep -> Bool
showNext step =
    step == CollaboratorsStep


showSkip : TutorialStep -> Bool
showSkip step =
    case step of
        AccountsStep ->
            False

        DeleteMovementStep ->
            False

        _ ->
            True


doneButton : Bool
doneButton =
    False


allowsTargetClick : TutorialStep -> Bool
allowsTargetClick step =
    case step of
        CollaboratorsStep ->
            False

        DeleteMovementStep ->
            True

        _ ->
            True
