program AudioDecoder;

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
  Default_RPM = 120; // оборотов в минуту
  sample_per_second = 44100; // частота дискрретизации
  SecPerMin = 60; // секунд в минуте
  half_row_width = 3; // ширина дорожки
  noise_threshold = 35; // допустимый уровень шума

  show_track = false; // показывать картинку и путь иглы // звук портитс€

procedure WriteSample(AudioStream: TStream; sample: Word);
begin
  AudioStream.Write(sample, sizeOf(sample));
end;

procedure SaveToWav(AudioStream: TStream; FileName: string);
var
  s: ansistring;
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
  WaveHeader.Freq := sample_per_second;
  WaveHeader.align := 2;
  WaveHeader.Bits := 8;
  WaveHeader.BytesPerSec := WaveHeader.Freq * WaveHeader.Ch * (WaveHeader.Bits div 8);
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
function ColorToGrayscale(color: TColor): byte;
var
  r, g, b: byte;
begin
  r := color and $000000FF;
  g := (color and $0000FF00) shr 8;
  b := (color and $00FF0000) shr 16;
  Result := round((r + g + b) / 3);
end;

function ColorToSample(color: TColor): Word;
var
  r, g, b: byte;
begin
  r := color and $000000FF;
  g := (color and $0000FF00) shr 8;
  b := (color and $00FF0000) shr 16;
  Result := r or (g shl 8);
end;

// вз€ть точку в радиальных координатах aka угол/рассто€ние от центра
function Pick(bmp: TBitmap; center: Tpoint; angle, radius: double; color: TColor = clRed): word;
var
  x, y: integer;
begin
  x := round(center.x + sin(angle) * radius);
  y := round(center.y + cos(angle) * radius);
  Result := ColorToSample(bmp.Canvas.Pixels[x, y]);
  if show_track then
    bmp.Canvas.Pixels[x, y] := color;
end;

// определим центр и внешний радиус пластинки
procedure DetectCenter(bmp: TBitmap; var center: Tpoint; var start_radius, end_radius: double);

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
      if abs(color - test_color) > noise_threshold then
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

var
  c, p1, p2, p3: Tpoint;
  x, y: integer;
  color, test_color: byte;
  A, b, M, D, E, F, g: double;
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
    if abs(color - test_color) > noise_threshold then
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
    if abs(color - test_color) > noise_threshold then
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
    if abs(color - test_color) > noise_threshold then
    begin
      p3 := Point(x, y);
      break;
    end;
    y := y - 1;
  end;
  // magic on // определение центра по 3м точкам
  A := p2.x - p1.x;
  b := p2.y - p1.y;
  M := p3.x - p1.x;
  D := p3.y - p1.y;
  E := A * (p1.x + p2.x) + b * (p1.y + p2.y);
  F := M * (p1.x + p3.x) + D * (p1.y + p3.y);
  g := 2 * (A * (p3.y - p2.y) - b * (p3.x - p2.x));
  if g = 0 then
    Exit;
  c.x := round((D * E - b * F) / g);
  c.y := round((A * F - M * E) / g);
  // magic off
  center := c;

  // найдЄм внутренний край и последнюю дорожку
  end_radius := GetRow(center, center, Point(0, 1)) + half_row_width;

  // найдЄм внешний край и первую дорожку
  start_radius := GetRow(center, Point(center.x, bmp.Height - 1), Point(0, -1));
end;

var
  pic: TPicture;
  bmp: TBitmap;
  AudioStream: TMemoryStream;

  center: Tpoint;
  delta, start_radius, end_radius, current_radius, angle: double;
  test_row_pixel, plate_color: byte;
  RPM: integer;
  sample: word;

begin
  if not TryStrToInt(paramstr(2), RPM) then
    RPM := Default_RPM;
  bmp := TBitmap.Create;
  try
    pic := TPicture.Create;
    try
      pic.LoadFromFile(paramstr(1));
      bmp.Assign(pic.Graphic);
    finally
      pic.Free;
    end;

    AudioStream := TMemoryStream.Create;
    try
      DetectCenter(bmp, center, start_radius, end_radius);

      // на сколько радиан нужно смещать иглу дл€ получени€ нужного семплрейта
      delta := (pi * 2) / (sample_per_second / (RPM / SecPerMin));

      current_radius := start_radius;

      angle := 0;
      plate_color := Pick(bmp, center, angle, current_radius - half_row_width * 2);
      while true do
      begin
        if angle > (pi * 2) then
          angle := 0;

        test_row_pixel := Pick(bmp, center, angle, current_radius - half_row_width, clGreen);
        if abs(plate_color - test_row_pixel) > noise_threshold then
        begin
          current_radius := current_radius - 0.1;
          test_row_pixel := Pick(bmp, center, angle, current_radius + half_row_width, clGreen);
          if abs(plate_color - test_row_pixel) > noise_threshold then
            current_radius := current_radius + 0.1;

        end;

        sample := Pick(bmp, center, angle, current_radius);
        WriteSample(AudioStream, sample);

        angle := angle + delta;

        if current_radius <= end_radius then
          break;
      end;

    finally
      SaveToWav(AudioStream, paramstr(1) + '.wav');
      AudioStream.Free;
    end;
  finally
    if show_track then
      bmp.SaveToFile('x.bmp');
    bmp.Free;
  end;

end.
