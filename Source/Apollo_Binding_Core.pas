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
    FCIndex: Integer;
    FControl: TComponent;
    FNativeEvent: TNotifyEvent;
    FPropName: string;
    FSource: TObject;
  public
    property CIndex: Integer read FCIndex write FCIndex;
    property Control: TComponent read FControl write FControl;
    property NativeEvent: TNotifyEvent read FNativeEvent write FNativeEvent;
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

  TBindingEngine = class abstract(TInterfacedObject)
  private
    FBindItemList: TObjectList<TBindItem>;
    FControlFreeNotification: TControlFreeNotification;
    procedure AddSourceFreeNotification(aSource: TObject);
    procedure AddControlFreeNotification(aControl: TComponent);
    procedure RemoveBindItems(const aBindItems: TArray<TBindItem>);
    procedure SourceFreeNotification(Sender: TObject);
  protected
    function AddBindItem(aSource: TObject; const aPropName: string;
      aControl: TComponent; const aIndex: Integer): TBindItem;
    function GetMatchedSourceProperty(const aControlNamePrefix, aControlName: string;
      const RttiProperties: TArray<TRttiProperty>): TRttiProperty;
    procedure BindPropertyToControl(aSource: TObject; aRttiProperty: TRttiProperty; aControl: TComponent); virtual; abstract;
    procedure DoBind(aSource: TObject; aControl: TComponent; const aControlNamePrefix: string;
      aRttiProperties: TArray<TRttiProperty>); virtual; abstract;
  public
    function GetBindItem(aControl: TComponent; const aIndex: Integer = 0): TBindItem;
    function GetBindItems(aControl: TComponent): TArray<TBindItem>; overload;
    function GetBindItems(aSource: TObject): TArray<TBindItem>; overload;
    procedure Bind(aSource: TObject; aRootControl: TComponent; const aControlNamePrefix: string = '');
    procedure Notify(aSource: TObject);
    procedure SingleBind(aSource: TObject; aControl: TComponent; const aIndex: Integer);
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

  FControlFreeNotification := TControlFreeNotification.Create(nil);
  FControlFreeNotification.FBindingEngine := Self;
end;

destructor TBindingEngine.Destroy;
begin
  FControlFreeNotification.Free;
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

function TBindingEngine.GetBindItem(aControl: TComponent; const aIndex: Integer): TBindItem;
var
  BindItem: TBindItem;
begin
  Result := nil;

  for BindItem in FBindItemList do
    if (BindItem.Control = aControl) and (BindItem.CIndex = aIndex) then
      Exit(BindItem);
end;

function TBindingEngine.GetBindItems(aControl: TComponent): TArray<TBindItem>;
var
  BindItem: TBindItem;
begin
  Result := [];

  for BindItem in FBindItemList do
    if BindItem.Control = aControl then
      Result := Result + [BindItem];
end;

function TBindingEngine.GetBindItems(aSource: TObject): TArray<TBindItem>;
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
  BindItems := GetBindItems(aSource);

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
  aControl: TComponent; const aIndex: Integer): TBindItem;
var
  BindItem: TBindItem;
begin
  BindItem := GetBindItem(aControl, aIndex);
  if Assigned(BindItem) then
    RemoveBindItems([BindItem]);

  Result := TBindItem.Create;
  Result.Source := aSource;
  Result.PropName := aPropName;
  Result.Control := aControl;
  Result.CIndex := aIndex;

  FBindItemList.Add(Result);
  AddControlFreeNotification(aControl);
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

procedure TBindingEngine.Bind(aSource: TObject; aRootControl: TComponent;
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

procedure TBindingEngine.SingleBind(aSource: TObject; aControl: TComponent;
  const aIndex: Integer);
begin
  AddBindItem(aSource, '', aControl, aIndex);
  AddSourceFreeNotification(aSource);
end;

procedure TBindingEngine.SourceFreeNotification(Sender: TObject);
var
  BindItems: TArray<TBindItem>;
begin
  BindItems := GetBindItems(Sender);
  RemoveBindItems(BindItems);
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
    BindItems := FBindingEngine.GetBindItems(AComponent);
    FBindingEngine.RemoveBindItems(BindItems);
  end;
end;

end.
