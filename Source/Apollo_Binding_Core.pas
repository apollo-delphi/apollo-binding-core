unit Apollo_Binding_Core;

interface

uses
  System.Classes,
  System.Rtti;

type
  ISourceFreeNotification = interface
  ['{087E30AF-C13E-4B9C-861F-42FFC335B747}']
    procedure AddFreeNotify(aNotifyEvent: TNotifyEvent);
  end;

  TBindingEngine = class abstract(TInterfacedObject)
  end;

  TBindAbstract = class abstract
  end;

implementation

end.
