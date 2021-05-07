unit Apollo_Binding_Core;

interface

uses
  Apollo_Types,
  System.Classes,
  System.Generics.Collections,
  System.Rtti;

type
  TBindItem = class
  strict private
    [weak]FControl: TObject;
    FPropName: string;
    [weak]FSecondaryControl: TObject;
    [weak]FSource: TObject;
  public
    property Control: TObject read FControl write FControl;
    property PropName: string read FPropName write FPropName;
    property SecondaryControl: TObject read FSecondaryControl write FSecondaryControl;
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
    procedure AddSourceFreeNotification(aSource: TObject);
    procedure AddControlFreeNotification(aControl: TComponent);
    procedure RemoveBindItems(const aBindItems: TArray<TBindItem>);
    procedure SourceFreeNotification(Sender: TObject);
  protected
    function AddBindItem(aSource: TObject; const aPropName: string; aControl: TObject): TBindItem;
    function GetMatchedSourceProperty(const aControlNamePrefix, aControlName: string;
      const RttiProperties: TArray<TRttiProperty>): TRttiProperty;
    function TryGetNativeEvent(aControl: TComponent; out aMethod: TMethod): Boolean;
    procedure BindPropertyToControl(aSource: TObject; aRttiProperty: TRttiProperty; aControl: TObject); virtual; abstract;
    procedure DoBind(aSource: TObject; aControl: TObject; const aControlNamePrefix: string;
      aRttiProperties: TArray<TRttiProperty>); virtual; abstract;
    procedure SetNativeEvent(aControl: TComponent; aMethod: TMethod);
  public
    function GetFirstBindItem(aControl: TObject): TBindItem;
    function GetBindItemsByControl(aControl: TObject): TArray<TBindItem>;
    function GetBindItemsBySource(aSource: TObject): TArray<TBindItem>;
    procedure Bind(aSource: TObject; aRootControl: TObject; const aControlNamePrefix: string = '');
    procedure Notify(aSource: TObject);
    procedure SingleBind(aSource: TObject; aControl: TObject);
    constructor Create;
    destructor Destroy; override;
  end;

implementation

uses
  System.SysUtils;

{ TBindingEngine }

constructor TBindingEngine.Create;
begin
  FBindItemList := TObjectList<TBindItem>.Create(False);
  FControlNativeEvents := TDictionary<TObject, TMethod>.Create;

  FControlFreeNotification := TControlFreeNotification.Create(nil);
  FControlFreeNotification.FBindingEngine := Self;
end;

destructor TBindingEngine.Destroy;
begin
  FControlFreeNotification.Free;
  FControlNativeEvents.Free;
  FBindItemList.Free;

  inherited;
end;

procedure TBindingEngine.RemoveBindItems(const aBindItems: TArray<TBindItem>);
var
  BindItem: TBindItem;
begin
  for BindItem in aBindItems do
  begin
    FBindItemList.Remove(BindItem);
    BindItem.Free;
  end;
end;

function TBindingEngine.GetFirstBindItem(aControl: TObject): TBindItem;
var
  BindItem: TBindItem;
begin
  Result := nil;

  for BindItem in FBindItemList do
    if BindItem.Control = aControl then
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

function TBindingEngine.GetBindItemsBySource(aSource: TObject): TArray<TBindItem>;
var
  BindItem: TBindItem;
begin
  Result := [];

  for BindItem in FBindItemList do
    if BindItem.Source = aSource then
      Result := Result + [BindItem];
end;

function TBindingEngine.GetMatchedSourceProperty(const aControlNamePrefix, aControlName: string;
  const RttiProperties: TArray<TRttiProperty>): TRttiProperty;
var
  RttiProperty: TRttiProperty;
begin
  Result := nil;

  for RttiProperty in RttiProperties do
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

procedure TBindingEngine.Notify(aSource: TObject);
var
  BindItem: TBindItem;
  BindItems: TArray<TBindItem>;
  RttiContext: TRttiContext;
  RttiProperty: TRttiProperty;
begin
  BindItems := GetBindItemsBySource(aSource);

  RttiContext := TRttiContext.Create;
  try
    for BindItem in BindItems do
    begin
      RttiProperty := RttiContext.GetType(aSource.ClassType).GetProperty(BindItem.PropName);
      BindPropertyToControl(aSource, RttiProperty, BindItem.Control);
    end;
  finally
    RttiContext.Free;
  end;
end;

function TBindingEngine.AddBindItem(aSource: TObject; const aPropName: string;
  aControl: TObject): TBindItem;
begin
  Result := TBindItem.Create;
  Result.Source := aSource;
  Result.PropName := aPropName;
  Result.Control := aControl;

  FBindItemList.Add(Result);
  if aControl.InheritsFrom(TComponent) then
    AddControlFreeNotification(TComponent(aControl));
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

procedure TBindingEngine.Bind(aSource: TObject; aRootControl: TObject;
  const aControlNamePrefix: string);
var
  RttiContext: TRttiContext;
  RttiProperties: TArray<TRttiProperty>;
begin
  RttiContext := TRttiContext.Create;
  try
    RttiProperties := RttiContext.GetType(aSource.ClassType).GetProperties;
    DoBind(aSource, aRootControl, aControlNamePrefix, RttiProperties);
    AddSourceFreeNotification(aSource);
  finally
    RttiContext.Free;
  end;
end;

procedure TBindingEngine.SetNativeEvent(aControl: TComponent; aMethod: TMethod);
begin
  if not FControlNativeEvents.ContainsKey(aControl) then
    FControlNativeEvents.Add(aControl, aMethod);
end;

procedure TBindingEngine.SingleBind(aSource: TObject; aControl: TObject);
begin
  AddBindItem(aSource, '', aControl);
  AddSourceFreeNotification(aSource);
end;

procedure TBindingEngine.SourceFreeNotification(Sender: TObject);
var
  BindItems: TArray<TBindItem>;
begin
  BindItems := GetBindItemsBySource(Sender);
  RemoveBindItems(BindItems);
end;

function TBindingEngine.TryGetNativeEvent(aControl: TComponent;
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
var
  BindItems: TArray<TBindItem>;
begin
  inherited;

  if Operation = opRemove then
  begin
    BindItems := FBindingEngine.GetBindItemsByControl(AComponent);
    FBindingEngine.RemoveBindItems(BindItems);

    if FBindingEngine.FControlNativeEvents.ContainsKey(AComponent) then
      FBindingEngine.FControlNativeEvents.Remove(AComponent);
  end;
end;

end.
