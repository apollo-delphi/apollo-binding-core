program Apollo_Binding_Core_Test;

{$STRONGLINKTYPES ON}

{$DEFINE UseVCL}
{DEFINE UseFMX}

uses
  {$IFDEF UseVCL}
  VCL.Forms,
  DUnitX.Loggers.GUI.VCL,
  {$ENDIF }
  {$IFDEF UseFMX}
  FMX.Forms,
  {$ENDIF }
  System.SysUtils,
  DUnitX.Loggers.Xml.NUnit,
  DUnitX.TestFramework,
  tstApollo_Binding_Core in 'tstApollo_Binding_Core.pas',
  Apollo_Binding_Core in 'Apollo_Binding_Core.pas';

begin
  Application.Initialize;
  Application.Title := 'DUnitX';
  {$IFDEF UseFMX}
  Application.CreateForm(TGUIXTestRunner, GUIXTestRunner);
  {$ENDIF}
  {$IFDEF UseVCL}
  Application.CreateForm(TGUIVCLTestRunner, GUIVCLTestRunner);
  {$ENDIF}
  Application.Run;
end.
