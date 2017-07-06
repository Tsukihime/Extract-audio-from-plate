program PlateMaker;

{$APPTYPE CONSOLE}

uses
  PngImage, Graphics, Types, classes, sysutils;

const
  Default_RPM = 120; // �������� � ������
  sample_per_second = 44100; // ������� ��������������
  SecPerMin = 60; // ������ � ������
  half_row_width = 3; // ������ �������
  noise_threshold = 35; // ���������� ������� ����

procedure Put(bmp: TBitmap; center: Tpoint; angle, radius: double;
  sample: Word);

  function SampleToColor(color: Word): Tcolor;
  var
    r, g, b: Byte;
  begin
    r := color and $00FF;
    g := (color and $FF00) shr 8;
    b := (r + g) div 2;
    Result := r or (g shl 8) or (b shl 16);
  end;

var
  x, y, i: integer;
  c_sample: Tcolor;
begin
  c_sample := SampleToColor(sample);
  radius := radius - half_row_width;
  for i := 0 to half_row_width * 2 - 2 do
  begin
    x := round(center.x + sin(angle) * (radius + i));
    y := round(center.y + cos(angle) * (radius + i));
    bmp.Canvas.Pixels[x, y] := c_sample;
  end;
end;

function parseCMD(var FilePath: string; var RPM: integer): boolean;
begin
  Result := false;

  if ParamCount <= 0 then
  begin
    writeln('usage:');
    writeln('PlateMaker InputWavFilePath [RPM]');
    writeln('Input WavFile params:');
    writeln('44100, 8 bit, mono');
    Exit;
  end;

  FilePath := paramstr(1);

  if not FileExists(FilePath) then
    Exit;

  if not TryStrToInt(paramstr(2), RPM) then
    RPM := Default_RPM;

  Result := true;
end;

var
  RPM: integer;
  bmp: TBitmap;
  pic: TPngImage;
  center: Tpoint;

  alfa, delta, start_radius, step: double;
  i: integer;
  dr: double;
  start_angle: double;
  rounds_count: integer;
  AudioStream: TFileStream;

  sample: Word;
  FilePath: string;

begin
  if not parseCMD(FilePath, RPM) then
    Exit;
  writeln('working...');

  bmp := TBitmap.Create;
  try
    bmp.Width := 4000;
    bmp.Height := bmp.Width;
    center := Point(bmp.Width div 2, bmp.Height div 2);
    bmp.PixelFormat := pf24bit;

    bmp.Canvas.Brush.color := clBlack;
    bmp.Canvas.FillRect(bmp.Canvas.ClipRect);

    bmp.Canvas.Brush.color := $3A3A3A;
    bmp.Canvas.Ellipse(50, 50, bmp.Width - 50, bmp.Width - 50);

    bmp.Canvas.Brush.color := clBlack;
    bmp.Canvas.Ellipse(center.x - 300, center.y - 300, center.x + 300,
      center.y + 300);

    AudioStream := TFileStream.Create(FilePath, fmOpenRead);
    try
      /// ����������� ��������� //////////////////
      rounds_count := 125;
      step := 12; // px
      start_radius := bmp.Width div 2 - 120;
      start_angle := 0;
      /// ////////////////////////////////////////

      delta := (pi * 2) / (sample_per_second / (RPM / SecPerMin));
      alfa := 0;
      for i := 0 to rounds_count do
      begin
        while alfa < (start_angle + pi * 2) do
        begin
          dr := start_radius - ((alfa - start_angle) / (pi * 2) * step);
          AudioStream.Read(sample, SizeOf(sample));
          Put(bmp, center, alfa, dr, sample);
          alfa := alfa + delta;
        end;
        alfa := start_angle;
        start_radius := start_radius - step;
      end;

    finally
      AudioStream.Free;
    end;
  finally
    pic := TPngImage.Create;
    try
      pic.Assign(bmp);
      pic.SaveToFile(FilePath + '.output.png');
    finally
      pic.Free;
    end;
    bmp.Free;
  end;
  writeln('Done.');

end.
