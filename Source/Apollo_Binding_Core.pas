unit Apollo_Binding_Core;

interface

uses
  System.Classes,
  System.Generics.Collections,
  System.Rtti;

type
  TBindItem = class
  strict private
    FControl: TObject;
    FNew: Boolean;
    FPropName: string;
    FSource: TObject;
  public
    property Control: TObject read FControl write FControl;
    property New: Boolean read FNew write FNew;
    property PropName: string read FPropName write FPropName;
    property Source: TObject read FSource write FSource;
  end;

  TBindingEngine = class;

  TControlFreeNotification = class(TComponent)
  private
    FBindingEngine: TBindingEngine;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  end;

  TBindingEngine = class abstract
  private
    FBindItemList: TObjectList<TBindItem>;
    FControlFreeNotification: TControlFreeNotification;
    FControlNativeEvents: TDictionary<TObject, TMethod>;
    FLastBindedControlItemIndex: Integer;
    function AddBindItem(aSource: TObject; aControl: TObject; aRttiProperty: TRttiProperty): TBindItem;
    function GetBindItem(aSource: TObject; aControl: TObject): TBindItem;
    function GetBindItemsByControl(aControl: TObject): TArray<TBindItem>;
    function GetBindItemsBySource(aSource: TObject): TArray<TBindItem>;
    function GetMatchedSourceProperty(const aControlNamePrefix, aControlName: string;
      const aSourceProperties: TArray<TRttiProperty>): TRttiProperty;
    procedure AddControlFreeNotification(aControl: TComponent);
    procedure AddSourceFreeNotification(aSource: TObject);
    procedure DoBind(aSource: TObject; aControl: TObject; aRttiProperty: TRttiProperty);
    procedure ProcessControl(const aControlNamePrefix: string; aControl, aSource: TObject;
      aSourceProperties: TArray<TRttiProperty>);
    procedure RemoveBindItemsByControl(aControl: TObject);
    procedure RemoveBindItemsBySource(aSource: TObject);
    procedure SourceFreeNotification(Sender: TObject);
  protected
    function GetFirstBindItem(aControl: TObject): TBindItem;
    function GetSourceFromControl(aControl: TObject): TObject; virtual; abstract;
    function IsValidControl(aControl: TObject; out aControlName: string;
      out aChildControls: TArray<TObject>): Boolean; virtual; abstract;
    function TryGetNativeEvent(aControl: TObject; out aMethod: TMethod): Boolean;
    procedure ApplyToControls(aBindItem: TBindItem; aRttiProperty: TRttiProperty); virtual; abstract;
    procedure SetLastBindedControlItemIndex(const aValue: Integer);
    procedure SetNativeEvent(aControl: TObject; aMethod: TMethod);
  public
    function BindToControlItem(aSource: TObject; aControl: TObject): Integer;
    function GetSource(aControl: TObject): TObject;
    procedure Bind(aSource: TObject; aRootControl: TObject; const aControlNamePrefix: string = '');
    procedure RemoveBind(aRootControl: TObject);
    constructor Create;
    destructor Destroy; override;
  end;

implementation

uses
  Apollo_Types,
  System.SysUtils;

{ TBindingEngine }

function TBindingEngine.AddBindItem(aSource, aControl: TObject; aRttiProperty: TRttiProperty): TBindItem;
begin
  Result := TBindItem.Create;
  Result.Source := aSource;
  Result.Control := aControl;
  Result.New := True;

  if Assigned(aRttiProperty) then
    Result.PropName := aRttiProperty.Name;

  FBindItemList.Add(Result);

  if aControl.InheritsFrom(TComponent) then
    AddControlFreeNotification(TComponent(aControl));

  AddSourceFreeNotification(aSource);
end;

procedure TBindingEngine.AddControlFreeNotification(aControl: TComponent);
begin
  aControl.FreeNotification(FControlFreeNotification);
end;

procedure TBindingEngine.AddSourceFreeNotification(aSource: TObject);
var
  SourceFreeNotify: ISourceFreeNotification;
begin
  if aSource.GetInterface(ISourceFreeNotification, SourceFreeNotify) then
    SourceFreeNotify.AddFreeNotify(SourceFreeNotification);
end;

procedure TBindingEngine.Bind(aSource, aRootControl: TObject;
  const aControlNamePrefix: string);
var
  RttiContext: TRttiContext;
  SourceProperties: TArray<TRttiProperty>;
begin
  RttiContext := TRttiContext.Create;
  try
    SourceProperties := RttiContext.GetType(aSource.ClassType).GetProperties;
    ProcessControl(aControlNamePrefix, aRootControl, aSource, SourceProperties);
  finally
    RttiContext.Free;
  end;
end;

function TBindingEngine.BindToControlItem(aSource, aControl: TObject): Integer;
begin
  DoBind(aSource, aControl, nil{aRttiProperty});
  Result := FLastBindedControlItemIndex;
end;

constructor TBindingEngine.Create;
begin
  FBindItemList := TObjectList<TBindItem>.Create(True{aOwnsObjects});
  FControlNativeEvents := TDictionary<TObject, TMethod>.Create;

  FControlFreeNotification := TControlFreeNotification.Create(nil);
  FControlFreeNotification.FBindingEngine := Self;
end;

destructor TBindingEngine.Destroy;
begin
  FBindItemList.Free;
  FControlNativeEvents.Free;
  FControlFreeNotification.Free;

  inherited;
end;

procedure TBindingEngine.DoBind(aSource, aControl: TObject; aRttiProperty: TRttiProperty);
var
  BindItem: TBindItem;
begin
  BindItem := GetBindItem(aSource, aControl);
  if not Assigned(BindItem) then
    BindItem := AddBindItem(aSource, aControl, aRttiProperty);

  FLastBindedControlItemIndex := -1;
  ApplyToControls(BindItem, aRttiProperty);
  BindItem.New := False;
end;

function TBindingEngine.GetBindItem(aSource, aControl: TObject): TBindItem;
var
  BindItem: TBindItem;
begin
  Result := nil;

  for BindItem in FBindItemList do
    if (BindItem.Source = aSource) and (BindItem.Control = aControl) then
      Exit(BindItem);
end;

function TBindingEngine.GetBindItemsByControl(aControl: TObject): TArray<TBindItem>;
var
  BindItem: TBindItem;
begin
  Result := [];

  for BindItem in FBindItemList do
    if BindItem.Control = aControl then
      Result := Result + [BindItem];
end;

function TBindingEngine.GetBindItemsBySource(
  aSource: TObject): TArray<TBindItem>;
var
  BindItem: TBindItem;
begin
  Result := [];

  for BindItem in FBindItemList do
    if BindItem.Source = aSource then
      Result := Result + [BindItem];
end;

function TBindingEngine.GetFirstBindItem(aControl: TObject): TBindItem;
var
  BindItem: TBindItem;
begin
  Result := nil;
  for BindItem in FBindItemList  do
    if BindItem.Control = aControl then
      Exit(BindItem);
end;

function TBindingEngine.GetMatchedSourceProperty(const aControlNamePrefix,
  aControlName: string;
  const aSourceProperties: TArray<TRttiProperty>): TRttiProperty;
var
  RttiProperty: TRttiProperty;
begin
  Result := nil;

  for RttiProperty in aSourceProperties do
  begin
    if RttiProperty.PropertyType.IsInstance or
       RttiProperty.PropertyType.IsRecord or
       RttiProperty.PropertyType.IsSet
    then
      Continue;

    if aControlName.ToUpper.EndsWith((aControlNamePrefix + RttiProperty.Name).ToUpper) then
      Exit(RttiProperty);
  end;
end;

function TBindingEngine.GetSource(aControl: TObject): TObject;
var
  BindItems: TArray<TBindItem>;
begin
  Result := nil;

  BindItems := GetBindItemsByControl(aControl);
  if Length(BindItems) = 1 then
    Result := BindItems[0].Source
  else
  if Length(BindItems) > 1 then
    Result := GetSourceFromControl(aControl);
end;

procedure TBindingEngine.ProcessControl(const aControlNamePrefix: string;
  aControl, aSource: TObject; aSourceProperties: TArray<TRttiProperty>);
var
  ChildControl: TObject;
  ChildControls: TArray<TObject>;
  ControlName: string;
  RttiProperty: TRttiProperty;
begin
  if IsValidControl(aControl, {out}ControlName, {out}ChildControls) then
  begin
    RttiProperty := GetMatchedSourceProperty(aControlNamePrefix, ControlName, aSourceProperties);
    if Assigned(RttiProperty) then
      DoBind(aSource, aControl, RttiProperty);

    for ChildControl in ChildControls do
      ProcessControl(aControlNamePrefix, ChildControl, aSource, aSourceProperties);
  end;
end;

procedure TBindingEngine.RemoveBindItemsByControl(aControl: TObject);
var
  BindItem: TBindItem;
  BindItems: TArray<TBindItem>;
begin
  BindItems := GetBindItemsByControl(aControl);

  for BindItem in BindItems do
    FBindItemList.Remove(BindItem);
end;

procedure TBindingEngine.RemoveBindItemsBySource(aSource: TObject);
var
  BindItem: TBindItem;
  BindItems: TArray<TBindItem>;
begin
  BindItems := GetBindItemsBySource(aSource);

  for BindItem in BindItems do
    FBindItemList.Remove(BindItem);
end;

procedure TBindingEngine.RemoveBind(aRootControl: TObject);
var
  ChildControl: TObject;
  ChildControls: TArray<TObject>;
  ControlName: string;
begin
  if IsValidControl(aRootControl, {out}ControlName, {out}ChildControls) then
  begin
    RemoveBindItemsByControl(aRootControl);

    for ChildControl in ChildControls do
      RemoveBind(ChildControl);
  end;
end;

procedure TBindingEngine.SetLastBindedControlItemIndex(const aValue: Integer);
begin
  FLastBindedControlItemIndex := aValue;
end;

procedure TBindingEngine.SetNativeEvent(aControl: TObject; aMethod: TMethod);
begin
  if not FControlNativeEvents.ContainsKey(aControl) then
    FControlNativeEvents.Add(aControl, aMethod);
end;

procedure TBindingEngine.SourceFreeNotification(Sender: TObject);
begin
  RemoveBindItemsBySource(Sender);
end;

function TBindingEngine.TryGetNativeEvent(aControl: TObject;
  out aMethod: TMethod): Boolean;
begin
  if FControlNativeEvents.TryGetValue(aControl, aMethod) then
    Result := True
  else
    Result := False;
end;

{ TControlFreeNotification }

procedure TControlFreeNotification.Notification(AComponent: TComponent;
  Operation: TOperation);
begin
  inherited;

  if Operation = opRemove then
    FBindingEngine.RemoveBindItemsByControl(AComponent);
end;

end.
