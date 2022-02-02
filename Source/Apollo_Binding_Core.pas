unit Apollo_Binding_Core;

interface

uses
  System.Classes,
  System.Generics.Collections,
  System.Rtti;

type
  TPopulateProc = reference to procedure(const aIndex: Integer);
  TOnNotifyProc = reference to procedure(Source: TObject);

  TBindItem = class
  strict private
    FControl: TObject;
    FNew: Boolean;
    FPopulateProc: TPopulateProc;
    FPropName: string;
    FSource: TObject;
    function StrToPropertyVal(aRttiProperty: TRttiProperty; const aValue: string): Variant;
  public
    function GetRttiProperty: TRttiProperty;
    procedure SetNewValue(const aValue: string);
    property Control: TObject read FControl write FControl;
    property New: Boolean read FNew write FNew;
    property PopulateProc: TPopulateProc read FPopulateProc write FPopulateProc;
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
  
  TSubscriber = record
  private
    function CheckKeyProp(aReferSource: TObject): Boolean;
  public
    KeyPropValue: Variant;
    OnNotifyProc: TOnNotifyProc;
    ReferClassType: TClass;
    ReferKeyPropName: string;
    Source: TObject;
    function CheckReferSource(aReferSource: TObject): Boolean;
  end;
  
  TBindingEngine = class abstract
  private
    FBindItemList: TObjectList<TBindItem>;
    FControlFreeNotification: TControlFreeNotification;
    FControlNativeEvents: TDictionary<TObject, TMethod>;
    FLastBindedControlItem: TObject;
    FLastBindedControlItemIndex: Integer;
    FSubscribers: TArray<TSubscriber>;
    function AddBindItem(aSource: TObject; aControl: TObject;
      aRttiProperty: TRttiProperty; aPopulateProc: TPopulateProc): TBindItem;
    function GetBindItem(aSource: TObject; aControl: TObject): TBindItem;
    function GetBindItemsByControl(aControl: TObject): TArray<TBindItem>;
    function GetBindItemsBySource(aSource: TObject): TArray<TBindItem>;
    function GetMatchedSourceProperty(const aSourcePropPrefix, aControlName: string;
      const aSourceProperties: TArray<TRttiProperty>): TRttiProperty;
    procedure AddControlFreeNotification(aControl: TComponent);
    procedure AddSourceFreeNotification(aSource: TObject);
    procedure DoBind(aSource: TObject; aControl: TObject; aRttiProperty: TRttiProperty; aPopulateProc: TPopulateProc);
    procedure ProcessControl(const aSourcePropPrefix: string; aControl, aSource: TObject;
      aSourceProperties: TArray<TRttiProperty>);
    procedure RemoveBindItemsByControl(aControl: TObject; const aRemoveFromNativeEvents: Boolean);
    procedure RemoveBindItemsBySource(aSource: TObject);
    procedure SourceFreeNotification(Sender: TObject);
  protected
    FControlParentItem: TObject;
    function GetFirstBindItemHavingProp(aControl: TObject): TBindItem;
    function GetSourceFromControl(aControl: TObject): TObject; virtual; abstract;
    function IsValidControl(aControl: TObject; out aControlName: string;
      out aChildControls: TArray<TObject>): Boolean; virtual; abstract;
    function PropertyValToStr(aRttiProperty: TRttiProperty; aSource: TObject): string;
    function TryGetNativeEvent(aControl: TObject; out aMethod: TMethod): Boolean;
    procedure ApplyToControls(aBindItem: TBindItem; aRttiProperty: TRttiProperty); virtual; abstract;
    procedure SetLastBindedControlItem(const aValue: TObject);
    procedure SetLastBindedControlItemIndex(const aValue: Integer);
    procedure SetNativeEvent(const aNewBind: Boolean; aControl: TObject; aMethod: TMethod);
  public
    function BindToControlItem(aSource: TObject; aControl: TObject; aPopulateProc: TPopulateProc): Integer; overload;
    function BindToControlItem(aSource: TObject; aControl: TObject; aControlParentItem: TObject): TObject; overload;
    function GetSource(aControl: TObject): TObject;
    procedure Bind(aSource: TObject; aRootControl: TObject; const aSourcePropPrefix: string = '');
    procedure Notify(aSource: TObject);
    procedure RemoveBind(aRootControl: TObject);
    procedure SubscribeNotification(aSource: TObject; aReferClassType: TClass; const aReferKeyPropName: string;
      const aKeyPropValue: Variant; aOnNotifyProc: TOnNotifyProc);
    constructor Create;
    destructor Destroy; override;
  end;

implementation

uses
  Apollo_Types,
  System.Character,
  System.SysUtils;

{ TBindingEngine }

function TBindingEngine.AddBindItem(aSource, aControl: TObject;
  aRttiProperty: TRttiProperty; aPopulateProc: TPopulateProc): TBindItem;
begin
  Result := TBindItem.Create;
  Result.Source := aSource;
  Result.Control := aControl;
  Result.PopulateProc := aPopulateProc;
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
  const aSourcePropPrefix: string);
var
  RttiContext: TRttiContext;
  SourceProperties: TArray<TRttiProperty>;
begin
  RttiContext := TRttiContext.Create;
  try
    SourceProperties := RttiContext.GetType(aSource.ClassType).GetProperties;
    ProcessControl(aSourcePropPrefix, aRootControl, aSource, SourceProperties);
  finally
    RttiContext.Free;
  end;
end;

function TBindingEngine.BindToControlItem(aSource, aControl,
  aControlParentItem: TObject): TObject;
begin
  FControlParentItem := aControlParentItem;
  DoBind(aSource, aControl, nil{aRttiProperty}, nil{aPopulateProc});
  Result := FLastBindedControlItem;
end;

function TBindingEngine.BindToControlItem(aSource, aControl: TObject; aPopulateProc: TPopulateProc): Integer;
begin
  DoBind(aSource, aControl, nil{aRttiProperty}, aPopulateProc);
  Result := FLastBindedControlItemIndex;
  if Assigned(aPopulateProc) then
    aPopulateProc(Result);
end;

constructor TBindingEngine.Create;
begin
  FBindItemList := TObjectList<TBindItem>.Create(True{aOwnsObjects});
  FControlNativeEvents := TDictionary<TObject, TMethod>.Create;
  FSubscribers := [];
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

procedure TBindingEngine.DoBind(aSource, aControl: TObject; aRttiProperty: TRttiProperty;
  aPopulateProc: TPopulateProc);
var
  BindItem: TBindItem;
begin
  BindItem := GetBindItem(aSource, aControl);
  if not Assigned(BindItem) then
    BindItem := AddBindItem(aSource, aControl, aRttiProperty, aPopulateProc);

  FLastBindedControlItem := nil;
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

function TBindingEngine.GetFirstBindItemHavingProp(aControl: TObject): TBindItem;
var
  BindItem: TBindItem;
begin
  Result := nil;
  for BindItem in FBindItemList  do
    if (BindItem.Control = aControl) and not BindItem.PropName.IsEmpty then
      Exit(BindItem);
end;

function TBindingEngine.GetMatchedSourceProperty(const aSourcePropPrefix,
  aControlName: string;
  const aSourceProperties: TArray<TRttiProperty>): TRttiProperty;
var
  ControlName: string;
  i: Integer;
  Index: Integer;
  RttiProperty: TRttiProperty;
begin
  Result := nil;

  if aControlName.Contains('_') then
    ControlName := aControlName.Split(['_'])[0]
  else
    ControlName := aControlName;

  Index := 0;
  for i := Low(ControlName) to High(ControlName) do
    if ControlName[i].IsUpper then
    begin
      Index := i - 1;
      Break;
    end;

  for RttiProperty in aSourceProperties do
  begin
    if RttiProperty.PropertyType.IsRecord or
       RttiProperty.PropertyType.IsSet
    then
      Continue;

    if ControlName.Substring(Index).ToUpper = (aSourcePropPrefix + RttiProperty.Name).ToUpper then
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

procedure TBindingEngine.Notify(aSource: TObject);
var
  BindItem: TBindItem;
  BindItems: TArray<TBindItem>;
  Index: Integer;
  RttiContext: TRttiContext;
  RttiProperty: TRttiProperty;
  Subscriber: TSubscriber;
begin
  BindItems := GetBindItemsBySource(aSource);
  for Subscriber in FSubscribers do
  begin
    if Subscriber.CheckReferSource(aSource) then
    begin
      BindItems := BindItems + GetBindItemsBySource(Subscriber.Source);
      if Assigned(Subscriber.OnNotifyProc) then
        Subscriber.OnNotifyProc(Subscriber.Source);
    end;
  end;

  RttiContext := TRttiContext.Create;
  try
    for BindItem in BindItems do
    begin
      if Assigned(BindItem.PopulateProc) then
      begin
        ApplyToControls(BindItem, nil{aRttiProperty});
        Index := FLastBindedControlItemIndex;
        BindItem.PopulateProc(Index);
      end
      else if not BindItem.PropName.IsEmpty then
      begin
        RttiProperty := RttiContext.GetType(BindItem.Source.ClassType).GetProperty(BindItem.PropName);
        ApplyToControls(BindItem, RttiProperty);
      end;
    end;
  finally
    RttiContext.Free;
  end;
end;

procedure TBindingEngine.ProcessControl(const aSourcePropPrefix: string;
  aControl, aSource: TObject; aSourceProperties: TArray<TRttiProperty>);
var
  ChildControl: TObject;
  ChildControls: TArray<TObject>;
  ControlName: string;
  RttiProperty: TRttiProperty;
begin
  if IsValidControl(aControl, {out}ControlName, {out}ChildControls) then
  begin
    RttiProperty := GetMatchedSourceProperty(aSourcePropPrefix, ControlName, aSourceProperties);
    if Assigned(RttiProperty) then
      DoBind(aSource, aControl, RttiProperty, nil{aPopulateProc});
  end;

  for ChildControl in ChildControls do
    ProcessControl(aSourcePropPrefix, ChildControl, aSource, aSourceProperties);
end;

function TBindingEngine.PropertyValToStr(aRttiProperty: TRttiProperty; aSource: TObject): string;
begin
  if aRttiProperty.PropertyType.Name = 'TDateTime' then
  begin
    if aRttiProperty.GetValue(aSource).AsExtended = 0 then
      Result := ''
    else
      Result := DateTimeToStr(aRttiProperty.GetValue(aSource).AsExtended);
  end
  else
    Result := aRttiProperty.GetValue(aSource).AsVariant;
end;

procedure TBindingEngine.RemoveBindItemsByControl(aControl: TObject;
  const aRemoveFromNativeEvents: Boolean);
var
  BindItem: TBindItem;
  BindItems: TArray<TBindItem>;
  Method: TMethod;
begin
  BindItems := GetBindItemsByControl(aControl);

  for BindItem in BindItems do
    FBindItemList.Remove(BindItem);

  if aRemoveFromNativeEvents and FControlNativeEvents.TryGetValue(aControl, {out}Method) then
    FControlNativeEvents.Remove(aControl);
end;

procedure TBindingEngine.RemoveBindItemsBySource(aSource: TObject);
var
  BindItem: TBindItem;
  BindItems: TArray<TBindItem>;
  i: Integer;
begin
  BindItems := GetBindItemsBySource(aSource);

  for BindItem in BindItems do
    FBindItemList.Remove(BindItem);

  for i := Length(FSubscribers) - 1 downto 0 do
    if FSubscribers[i].Source = aSource then
      Delete(FSubscribers, i, 1);
end;

procedure TBindingEngine.RemoveBind(aRootControl: TObject);
var
  ChildControl: TObject;
  ChildControls: TArray<TObject>;
  ControlName: string;
begin
  IsValidControl(aRootControl, {out}ControlName, {out}ChildControls);

  RemoveBindItemsByControl(aRootControl, False{aRemoveFromNativeEvents});
  for ChildControl in ChildControls do
    RemoveBind(ChildControl);
end;

procedure TBindingEngine.SetLastBindedControlItem(const aValue: TObject);
begin
  FLastBindedControlItem := aValue;
end;

procedure TBindingEngine.SetLastBindedControlItemIndex(const aValue: Integer);
begin
  FLastBindedControlItemIndex := aValue;
end;

procedure TBindingEngine.SetNativeEvent(const aNewBind: Boolean; aControl: TObject; aMethod: TMethod);
begin
  if aNewBind and
     not FControlNativeEvents.ContainsKey(aControl)
  then
    FControlNativeEvents.Add(aControl, aMethod);
end;

procedure TBindingEngine.SourceFreeNotification(Sender: TObject);
begin
  RemoveBindItemsBySource(Sender);
end;

procedure TBindingEngine.SubscribeNotification(aSource: TObject; aReferClassType: TClass;
  const aReferKeyPropName: string; const aKeyPropValue: Variant; aOnNotifyProc: TOnNotifyProc);
var
  AlreadySubscribed: Boolean;
  i: Integer;
  Subscriber: TSubscriber;
begin
  AlreadySubscribed := False;
  for i := 0 to Length(FSubscribers) - 1 do
    if (FSubscribers[i].Source = aSource) and (FSubscribers[i].ReferClassType = aReferClassType) then
    begin
      AlreadySubscribed := True;
      Break;
    end;

  if not(AlreadySubscribed) then
  begin
    Subscriber.Source := aSource;
    Subscriber.ReferClassType := aReferClassType;
    Subscriber.ReferKeyPropName := aReferKeyPropName;
    Subscriber.KeyPropValue := aKeyPropValue;
    Subscriber.OnNotifyProc := aOnNotifyProc;

    FSubscribers := FSubscribers + [Subscriber];
  end;
end;

function TBindingEngine.TryGetNativeEvent(aControl: TObject;
  out aMethod: TMethod): Boolean;
begin
  if FControlNativeEvents.TryGetValue(aControl, aMethod) then
  begin
    if Assigned(aMethod.Code) then
      Result := True
    else
      Result := False;
  end
  else
    Result := False;
end;

{ TControlFreeNotification }

procedure TControlFreeNotification.Notification(AComponent: TComponent;
  Operation: TOperation);
begin
  inherited;

  if Operation = opRemove then
    FBindingEngine.RemoveBindItemsByControl(AComponent, True{aRemoveFromNativeEvents});
end;

{ TSubscriber }

function TSubscriber.CheckKeyProp(aReferSource: TObject): Boolean;
var
  RttiContext: TRttiContext;
  RttiProperty: TRttiProperty;
begin
  Result := False;
  RttiContext := TRttiContext.Create;
  try
    RttiProperty := RttiContext.GetType(ReferClassType).GetProperty(ReferKeyPropName);
    if Assigned(RttiProperty) and (RttiProperty.GetValue(aReferSource).AsVariant = KeyPropValue) then
      Result := True;
  finally
    RttiContext.Free;
  end;
end;

function TSubscriber.CheckReferSource(aReferSource: TObject): Boolean;
begin
  Result := False;

  if (aReferSource.ClassType = ReferClassType) and
     (aReferSource <> Source) and
     CheckKeyProp(aReferSource)
  then
    Result := True;
end;

{ TBindItem }

function TBindItem.GetRttiProperty: TRttiProperty;
var
  RttiContext: TRttiContext;
  RttiProperties: TArray<TRttiProperty>;
  RttiProperty: TRttiProperty;
begin
  Result := nil;

  RttiContext := TRttiContext.Create;
  try
    RttiProperties := RttiContext.GetType(Source.ClassType).GetProperties;
    for RttiProperty in RttiProperties do
      if RttiProperty.Name = PropName then
        Exit(RttiProperty);
  finally
    RttiContext.Free;
  end;
end;

procedure TBindItem.SetNewValue(const aValue: string);
var
  RttiProperty: TRttiProperty;
  Value: Variant;
begin
  RttiProperty := GetRttiProperty;
  Value := StrToPropertyVal(RttiProperty, aValue);
  RttiProperty.SetValue(Source, TValue.FromVariant(Value));
end;

function TBindItem.StrToPropertyVal(aRttiProperty: TRttiProperty;
  const aValue: string): Variant;
begin
  if aRttiProperty.PropertyType.Name = 'TDateTime' then
    Result := StrToDateTimeDef(aValue, 0)
  else
  if aRttiProperty.PropertyType.TypeKind in [tkInteger] then
    Result := StrToIntDef(aValue, 0)
  else
  if aRttiProperty.PropertyType.TypeKind in [tkFloat] then
    Result := StrToFloatDef(aValue, 0)
  else
    Result := aValue;
end;

end.
