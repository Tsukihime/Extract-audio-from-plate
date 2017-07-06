program AudioDecoder;

{$APPTYPE CONSOLE}

uses
  PngImage, Graphics, Types, classes, sysutils;

type
  TWaveHeader = record
    idRiff: array [0 .. 3] of ansichar;
    RiffLen: longint;
    idWave: array [0 .. 3] of ansichar;
    idFmt: array [0 .. 3] of ansichar;
    InfoLen: longint;
    WaveType: smallint;
    Ch: smallint;
    Freq: longint;
    BytesPerSec: longint;
    align: smallint;
    Bits: smallint;
    idData: array [0 .. 3] of ansichar;
    DataLen: longint;
  end;

const
  DefaultRPM = 120; // оборотов в минуту
  SamplePerSecond = 44100; // частота дискрретизации
  SecPerMin = 60; // секунд в минуте
  HalfRowWidth = 3; // ширина дорожки
  NoiseThreshold = 35; // допустимый уровень шума

  ShowTrack = false; // показывать картинку и путь иглы // звук портитс€

procedure SaveToWav(AudioStream: TStream; FileName: string);
var
  StreamSize: Cardinal;
  WaveHeader: TWaveHeader;
begin
  StreamSize := AudioStream.Size;
  WaveHeader.idRiff := 'RIFF';
  WaveHeader.RiffLen := StreamSize + $24;
  WaveHeader.idWave := 'WAVE';
  WaveHeader.idFmt := 'fmt ';
  WaveHeader.InfoLen := 16;
  WaveHeader.WaveType := 1;
  WaveHeader.Ch := 2;
  WaveHeader.Freq := SamplePerSecond;
  WaveHeader.align := 2;
  WaveHeader.Bits := 8;
  WaveHeader.BytesPerSec := WaveHeader.Freq * WaveHeader.Ch *
    (WaveHeader.Bits div 8);
  WaveHeader.idData := 'data';
  WaveHeader.DataLen := StreamSize;

  AudioStream.Seek(soFromBeginning, 0);
  with TFileStream.Create(FileName, fmCreate) do
  begin
    write(WaveHeader, SizeOf(TWaveHeader));
    CopyFrom(AudioStream, AudioStream.Size);
    Free;
  end;
end;

// переведЄм цвет в оттенки серого
function ColorToGrayscale(color: TColor): Byte;
var
  r, g, b: Byte;
begin
  r := color and $000000FF;
  g := (color and $0000FF00) shr 8;
  b := (color and $00FF0000) shr 16;
  Result := round((r + g + b) / 3);
end;

function ColorToSample(color: TColor): Word;
var
  r, g: Byte;
begin
  r := color and $000000FF;
  g := (color and $0000FF00) shr 8;
  Result := r or (g shl 8);
end;

// вз€ть точку в радиальных координатах aka угол/рассто€ние от центра
function Pick(bmp: TBitmap; center: Tpoint; angle, radius: double;
  MarkColor: TColor = clRed): Word;
var
  x, y: integer;
  pixel: TColor;
begin
  x := round(center.x + sin(angle) * radius);
  y := round(center.y + cos(angle) * radius);
  pixel := bmp.Canvas.Pixels[x, y];
  Result := ColorToSample(pixel);
  if ShowTrack then
    bmp.Canvas.Pixels[x, y] := MarkColor;
end;

// определим центр и внешний радиус пластинки
procedure DetectCenter(bmp: TBitmap; var center: Tpoint;
  var StartRadius, EndRadius: double);

  function GetRow(center_point, start_point, search_vector: Tpoint): double;
  var
    x, y: integer;
    jumps: integer;
    color, test_color: TColor;
  begin
    Result := -1;
    x := start_point.x;
    y := start_point.y;
    jumps := 0;
    color := ColorToGrayscale(bmp.Canvas.Pixels[x, y]);
    while (x >= 0) and (x < bmp.Width) and (y >= 0) and (y < bmp.Height) do
    begin
      test_color := ColorToGrayscale(bmp.Canvas.Pixels[x, y]);
      if abs(color - test_color) > NoiseThreshold then
      begin
        color := ColorToGrayscale(bmp.Canvas.Pixels[x, y]);
        jumps := jumps + 1;
        if jumps >= 2 then
        begin
          Result := sqrt(sqr(center_point.x - x) + sqr(center_point.y - y));
          break;
        end;
      end;
      x := x + search_vector.x;
      y := y + search_vector.y;
    end;
  end;

  function GetCircleCenterFrom3Points(p1, p2, p3: Tpoint): Tpoint;
  // определение центра по 3м точкам
  var
    A, b, M, D, E, F, g: double;
  begin
    A := p2.x - p1.x;
    b := p2.y - p1.y;
    M := p3.x - p1.x;
    D := p3.y - p1.y;

    E := A * (p1.x + p2.x) + b * (p1.y + p2.y);
    F := M * (p1.x + p3.x) + D * (p1.y + p3.y);
    g := 2 * (A * (p3.y - p2.y) - b * (p3.x - p2.x));
    if g = 0 then
      Exit;
    Result.x := round((D * E - b * F) / g);
    Result.y := round((A * F - M * E) / g);
  end;

var
  c, p1, p2, p3: Tpoint;
  x, y: integer;
  color, test_color: Byte;

begin
  // предполагаемый центр
  c := Point(bmp.Width div 2, bmp.Height div 2);
  color := ColorToGrayscale(bmp.Canvas.Pixels[c.x, c.y]);
  // теперь нужно найти 3 точки внутренней окружности
  // дл€ этого бежим из центра в 3х направлени€х пока
  // €ркость пиксела не станет отличатс€ от предыдущего
  // более чем уровень шума (noise_threshold)

  // p1
  x := c.x;
  y := c.y;
  while x < bmp.Width - 1 do
  begin
    test_color := ColorToGrayscale(bmp.Canvas.Pixels[x, y]);
    if abs(color - test_color) > NoiseThreshold then
    begin
      p1 := Point(x, y);
      break;
    end;
    x := x + 1;
  end;

  // p2
  x := c.x;
  while x >= 0 do
  begin
    test_color := ColorToGrayscale(bmp.Canvas.Pixels[x, y]);
    if abs(color - test_color) > NoiseThreshold then
    begin
      p2 := Point(x, y);
      break;
    end;
    x := x - 1;
  end;

  // p3
  y := c.y;
  x := c.x;
  while y >= 0 do
  begin
    test_color := ColorToGrayscale(bmp.Canvas.Pixels[x, y]);
    if abs(color - test_color) > NoiseThreshold then
    begin
      p3 := Point(x, y);
      break;
    end;
    y := y - 1;
  end;

  center := GetCircleCenterFrom3Points(p1, p2, p3);

  // найдЄм внутренний край и последнюю дорожку
  EndRadius := GetRow(center, center, Point(0, 1)) + HalfRowWidth;

  // найдЄм внешний край и первую дорожку
  StartRadius := GetRow(center, Point(center.x, bmp.Height - 1), Point(0, -1));
end;

procedure LoadPicture(bmp: TBitmap; FilePath: string);
var
  pic: TPicture;
begin
  pic := TPicture.Create;
  try
    pic.LoadFromFile(FilePath);
    bmp.Assign(pic.Graphic);
  finally
    pic.Free;
  end;
end;

function parseCMD(var FilePath: string; var RPM: integer): boolean;
begin
  Result := false;

  if ParamCount <= 0 then
  begin
    writeln('usage:');
    writeln('AudioDecoder PlatePictureFilePath [RPM]');
    Exit;
  end;

  FilePath := paramstr(1);

  if not FileExists(FilePath) then
    Exit;

  if not TryStrToInt(paramstr(2), RPM) then
    RPM := DefaultRPM;

  Result := true;
end;

var
  bmp: TBitmap;
  AudioStream: TMemoryStream;

  center: Tpoint;
  delta, StartRadius, EndRadius, CurrentRadius, CurrentAngle: double;
  test_row_pixel, PlateColor: Byte;
  RPM: integer;
  sample: Word;

  FilePath: string;

begin
  if not parseCMD(FilePath, RPM) then
    Exit;

  writeln('working...');

  bmp := TBitmap.Create;
  try
    LoadPicture(bmp, FilePath);
    DetectCenter(bmp, center, StartRadius, EndRadius);

    // на сколько радиан нужно смещать иглу дл€ получени€ нужного семплрейта
    delta := (pi * 2) / (SamplePerSecond / (RPM / SecPerMin));

    CurrentRadius := StartRadius;
    CurrentAngle := 0;
    PlateColor := Pick(bmp, center, CurrentAngle,
      CurrentRadius - HalfRowWidth * 2);

    AudioStream := TMemoryStream.Create;
    try

      while true do
      begin
        if CurrentAngle > (pi * 2) then
          CurrentAngle := 0;

        test_row_pixel := Pick(bmp, center, CurrentAngle,
          CurrentRadius - HalfRowWidth, clGreen);
        if abs(PlateColor - test_row_pixel) > NoiseThreshold then
        begin
          CurrentRadius := CurrentRadius - 0.1;
          test_row_pixel := Pick(bmp, center, CurrentAngle,
            CurrentRadius + HalfRowWidth, clGreen);
          if abs(PlateColor - test_row_pixel) > NoiseThreshold then
            CurrentRadius := CurrentRadius + 0.1;
        end;

        sample := Pick(bmp, center, CurrentAngle, CurrentRadius);
        AudioStream.Write(sample, SizeOf(sample));

        CurrentAngle := CurrentAngle + delta;

        if CurrentRadius <= EndRadius then
          break;
      end;

    finally
      SaveToWav(AudioStream, FilePath + '.wav');
      AudioStream.Free;
    end;
  finally
    if ShowTrack then
      bmp.SaveToFile(FilePath + '.track.bmp');

    bmp.Free;
  end;

  writeln('Done.');

end.
