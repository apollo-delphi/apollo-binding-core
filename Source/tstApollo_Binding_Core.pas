unit tstApollo_Binding_Core;

//test unit

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMyTestObject = class
  public
  end;

implementation

initialization
  TDUnitX.RegisterTestFixture(TMyTestObject);

end.
