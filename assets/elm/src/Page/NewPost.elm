module Page.NewPost exposing (Model, Msg(..), consumeEvent, init, setup, teardown, title, update, view)

import Avatar
import Browser.Navigation as Nav
import Device exposing (Device)
import Event exposing (Event)
import File exposing (File)
import Globals exposing (Globals)
import Group exposing (Group)
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Icons
import Id exposing (Id)
import Json.Decode as Decode
import Layout.SpaceDesktop
import Layout.SpaceMobile
import ListHelpers exposing (insertUniqueBy, removeBy)
import Mutation.CreateGroup as CreateGroup
import PostEditor exposing (PostEditor)
import Query.SetupInit as SetupInit
import Repo exposing (Repo)
import Route exposing (Route)
import Route.Group
import Route.Groups
import Route.NewPost exposing (Params)
import Scroll
import Session exposing (Session)
import Space exposing (Space)
import SpaceUser exposing (SpaceUser)
import SpaceUserLists
import Task exposing (Task)
import ValidationError exposing (ValidationError, errorView, errorsFor, isInvalid)
import Vendor.Keys as Keys exposing (Modifier(..), enter, onKeydown, preventDefault)
import View.Helpers exposing (setFocus, viewIf)



-- MODEL


type alias Model =
    { params : Params
    , viewerId : Id
    , spaceId : Id
    , bookmarkIds : List Id
    , postComposer : PostEditor
    , isSubmitting : Bool
    , errors : List ValidationError

    -- MOBILE
    , showNav : Bool
    , showSidebar : Bool
    }


type alias Data =
    { viewer : SpaceUser
    , space : Space
    , bookmarks : List Group
    }


resolveData : Repo -> Model -> Maybe Data
resolveData repo model =
    Maybe.map3 Data
        (Repo.getSpaceUser model.viewerId repo)
        (Repo.getSpace model.spaceId repo)
        (Just <| Repo.getGroups model.bookmarkIds repo)



-- PAGE PROPERTIES


title : Model -> String
title model =
    "New Post"



-- LIFECYCLE


init : Params -> Globals -> Task Session.Error ( Globals, Model )
init params globals =
    globals.session
        |> SetupInit.request (Route.NewPost.getSpaceSlug params)
        |> Task.map (buildModel params globals)


buildModel : Params -> Globals -> ( Session, SetupInit.Response ) -> ( Globals, Model )
buildModel params globals ( newSession, resp ) =
    let
        model =
            Model
                params
                resp.viewerId
                resp.spaceId
                resp.bookmarkIds
                (PostEditor.init "post-composer")
                False
                []
                False
                False

        newRepo =
            Repo.union resp.repo globals.repo
    in
    ( { globals | session = newSession, repo = newRepo }, model )


setup : Model -> Cmd Msg
setup model =
    Cmd.batch
        [ setFocus "name" NoOp
        , Scroll.toDocumentTop NoOp
        ]


teardown : Model -> Cmd Msg
teardown model =
    Cmd.none



-- UPDATE


type Msg
    = NoOp
    | PostEditorEventReceived Decode.Value
    | NewPostBodyChanged String
    | NewPostFileAdded File
    | NewPostFileUploadProgress Id Int
    | NewPostFileUploaded Id Id String
    | NewPostFileUploadError Id
      -- MOBILE
    | NavToggled
    | SidebarToggled
    | ScrollTopClicked


update : Msg -> Globals -> Model -> ( ( Model, Cmd Msg ), Globals )
update msg globals model =
    case msg of
        NoOp ->
            noCmd globals model

        PostEditorEventReceived value ->
            case PostEditor.decodeEvent value of
                PostEditor.LocalDataFetched id body ->
                    if id == PostEditor.getId model.postComposer then
                        let
                            newPostComposer =
                                PostEditor.setBody body model.postComposer
                        in
                        ( ( { model | postComposer = newPostComposer }
                          , Cmd.none
                          )
                        , globals
                        )

                    else
                        noCmd globals model

                PostEditor.Unknown ->
                    noCmd globals model

        NewPostBodyChanged value ->
            let
                newPostComposer =
                    PostEditor.setBody value model.postComposer
            in
            ( ( { model | postComposer = newPostComposer }
              , PostEditor.saveLocal newPostComposer
              )
            , globals
            )

        NewPostFileAdded file ->
            noCmd globals { model | postComposer = PostEditor.addFile file model.postComposer }

        NewPostFileUploadProgress clientId percentage ->
            noCmd globals { model | postComposer = PostEditor.setFileUploadPercentage clientId percentage model.postComposer }

        NewPostFileUploaded clientId fileId url ->
            let
                newPostComposer =
                    model.postComposer
                        |> PostEditor.setFileState clientId (File.Uploaded fileId url)

                cmd =
                    newPostComposer
                        |> PostEditor.insertFileLink fileId
            in
            ( ( { model | postComposer = newPostComposer }, cmd ), globals )

        NewPostFileUploadError clientId ->
            noCmd globals { model | postComposer = PostEditor.setFileState clientId File.UploadError model.postComposer }

        NavToggled ->
            ( ( { model | showNav = not model.showNav }, Cmd.none ), globals )

        SidebarToggled ->
            ( ( { model | showSidebar = not model.showSidebar }, Cmd.none ), globals )

        ScrollTopClicked ->
            ( ( model, Scroll.toDocumentTop NoOp ), globals )


noCmd : Globals -> Model -> ( ( Model, Cmd Msg ), Globals )
noCmd globals model =
    ( ( model, Cmd.none ), globals )


redirectToLogin : Globals -> Model -> ( ( Model, Cmd Msg ), Globals )
redirectToLogin globals model =
    ( ( model, Route.toLogin ), globals )



-- EVENTS


consumeEvent : Globals -> Event -> Model -> ( Model, Cmd Msg )
consumeEvent globals event model =
    case event of
        Event.GroupBookmarked group ->
            ( { model | bookmarkIds = insertUniqueBy identity (Group.id group) model.bookmarkIds }, Cmd.none )

        Event.GroupUnbookmarked group ->
            ( { model | bookmarkIds = removeBy identity (Group.id group) model.bookmarkIds }, Cmd.none )

        _ ->
            ( model, Cmd.none )



-- VIEW


view : Globals -> Model -> Html Msg
view globals model =
    let
        spaceUsers =
            SpaceUserLists.resolveList globals.repo model.spaceId globals.spaceUserLists
    in
    case resolveData globals.repo model of
        Just data ->
            resolvedView globals spaceUsers model data

        Nothing ->
            text "Something went wrong."


resolvedView : Globals -> List SpaceUser -> Model -> Data -> Html Msg
resolvedView globals spaceUsers model data =
    case globals.device of
        Device.Desktop ->
            resolvedDesktopView globals spaceUsers model data

        Device.Mobile ->
            resolvedMobileView globals spaceUsers model data



-- DESKTOP


resolvedDesktopView : Globals -> List SpaceUser -> Model -> Data -> Html Msg
resolvedDesktopView globals spaceUsers model data =
    let
        config =
            { space = data.space
            , spaceUser = data.viewer
            , bookmarks = data.bookmarks
            , currentRoute = globals.currentRoute
            , flash = globals.flash
            , showKeyboardCommands = globals.showKeyboardCommands
            }
    in
    Layout.SpaceDesktop.layout config
        [ div [ class "mx-auto px-8 py-6 max-w-lg leading-normal" ]
            [ desktopPostComposerView model.spaceId model.postComposer data.viewer spaceUsers
            ]
        ]


desktopPostComposerView : Id -> PostEditor -> SpaceUser -> List SpaceUser -> Html Msg
desktopPostComposerView spaceId editor currentUser spaceUsers =
    let
        config =
            { editor = editor
            , spaceId = spaceId
            , spaceUsers = spaceUsers
            , onFileAdded = NewPostFileAdded
            , onFileUploadProgress = NewPostFileUploadProgress
            , onFileUploaded = NewPostFileUploaded
            , onFileUploadError = NewPostFileUploadError
            , classList = []
            }
    in
    PostEditor.wrapper config
        [ label [ class "composer mb-4" ]
            [ div [ class "flex" ]
                [ div [ class "flex-no-shrink mr-2" ] [ SpaceUser.avatar Avatar.Medium currentUser ]
                , div [ class "flex-grow pl-2 pt-2" ]
                    [ textarea
                        [ id (PostEditor.getTextareaId editor)
                        , class "w-full h-16 no-outline bg-transparent text-dusty-blue-darkest resize-none leading-normal"
                        , placeholder "What's on your mind?"
                        , onInput NewPostBodyChanged

                        -- , onKeydown preventDefault [ ( [ Keys.Meta ], enter, \event -> NewPostSubmit ) ]
                        , readonly (PostEditor.isSubmitting editor)
                        , value (PostEditor.getBody editor)
                        , tabindex 1
                        ]
                        []
                    , PostEditor.filesView editor
                    , div [ class "flex flex-wrap" ]
                        [ div [ class "mb-2 mr-2 pl-2 text-sm font-bold bg-turquoise rounded text-white" ]
                            [ text "Engineers"
                            , button [ class "mx-1 px-1 font-bold text-sm text-white rounded opacity-75" ] [ text "×" ]
                            ]
                        , div [ class "flex-grow relative" ]
                            [ input [ type_ "text", class "mb-2 w-full block text-sm no-outline text-dusty-blue-darkest bg-transparent", placeholder "Which group?", tabindex 2 ] []
                            , div [ class "absolute py-1 pin-l w-32 bg-white rounded shadow-md z-20", style "top" "100%" ]
                                [ button [ class "px-2 py-1 text-sm text-left font-bold bg-grey text-dusty-blue-darker w-full" ] [ text "Everyone" ]
                                , button [ class "px-2 py-1 text-sm text-left font-normal text-dusty-blue-darker w-full" ] [ text "Engineering" ]
                                ]
                            ]
                        ]
                    , div [ class "flex items-baseline justify-end" ]
                        [ button
                            [ class "btn btn-blue btn-md"

                            -- , onClick NewPostSubmit
                            , disabled (PostEditor.isUnsubmittable editor)
                            , tabindex 3
                            ]
                            [ text "Send" ]
                        ]
                    ]
                ]
            ]
        ]



-- MOBILE


resolvedMobileView : Globals -> List SpaceUser -> Model -> Data -> Html Msg
resolvedMobileView globals spaceUsers model data =
    let
        config =
            { space = data.space
            , spaceUser = data.viewer
            , bookmarks = data.bookmarks
            , currentRoute = globals.currentRoute
            , flash = globals.flash
            , title = "New Post"
            , showNav = model.showNav
            , onNavToggled = NavToggled
            , onSidebarToggled = SidebarToggled
            , onScrollTopClicked = ScrollTopClicked
            , onNoOp = NoOp
            , leftControl = Layout.SpaceMobile.NoControl
            , rightControl = Layout.SpaceMobile.NoControl
            }
    in
    Layout.SpaceMobile.layout config
        []
