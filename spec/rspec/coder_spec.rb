require 'spec_helper'

RSpec.describe 'Complex coder', type: :helper do
  let(:coder) { Torque::PostgreSQL::Coder }

  context 'on decode' do

    context 'one dimensional arrays' do
      it 'returns an empty array' do
        expect(coder.decode(%[{}])).to eql []
      end

      it 'returns an array of strings' do
        expect(coder.decode(%[{1,2,3}])).to eql ['1','2','3']
      end

      it 'returns an array of strings, with nils replacing NULL characters' do
        expect(coder.decode(%[{1,,NULL}])).to eql ['1',nil,nil]
      end

      it 'returns an array with the word NULL' do
        expect(coder.decode(%[{1,"NULL",3}])).to eql ['1','NULL','3']
      end

      it 'returns an array of strings when containing commas in a quoted string' do
        expect(coder.decode(%[{1,"2,3",4}])).to eql ['1','2,3','4']
      end

      it 'returns an array of strings when containing an escaped quote' do
        expect(coder.decode(%[{1,"2\\",3",4}])).to eql ['1','2",3','4']
      end

      it 'returns an array of strings when containing an escaped backslash' do
        expect(coder.decode(%[{1,"2\\\\",3,4}])).to eql ['1','2\\','3','4']
        expect(coder.decode(%[{1,"2\\\\\\",3",4}])).to eql ['1','2\\",3','4']
      end

      it 'returns an array containing empty strings' do
        expect(coder.decode(%[{1,"",3,""}])).to eql ['1', '', '3', '']
      end

      it 'returns an array containing unicode strings' do
        expect(coder.decode(%[{"Paragraph 399(b)(i) – “valid leave” – meaning"}])).to eq(['Paragraph 399(b)(i) – “valid leave” – meaning'])
      end
    end

    context 'two dimensional arrays' do
      it 'returns an empty array' do
        expect(coder.decode(%[{{}}])).to eql [[]]
        expect(coder.decode(%[{{},{}}])).to eql [[],[]]
      end

      it 'returns an array of strings with a sub array' do
        expect(coder.decode(%[{1,{2,3},4}])).to eql ['1',['2','3'],'4']
      end

      it 'returns an array of strings with a sub array' do
        expect(coder.decode(%[{1,{"2,3"},4}])).to eql ['1',['2,3'],'4']
      end

      it 'returns an array of strings with a sub array and a quoted }' do
        expect(coder.decode(%[{1,{"2,}3",,NULL},4}])).to eql ['1',['2,}3',nil,nil],'4']
      end

      it 'returns an array of strings with a sub array and a quoted {' do
        expect(coder.decode(%[{1,{"2,{3"},4}])).to eql ['1',['2,{3'],'4']
      end

      it 'returns an array of strings with a sub array and a quoted { and escaped quote' do
        expect(coder.decode(%[{1,{"2\\",{3"},4}])).to eql ['1',['2",{3'],'4']
      end

      it 'returns an array of strings with a sub array with empty strings' do
        expect(coder.decode(%[{1,{""},4,{""}}])).to eql ['1',[''],'4',['']]
      end
    end

    context 'three dimensional arrays' do
      it 'returns an empty array' do
        expect(coder.decode(%[{{{}}}])).to eql [[[]]]
        expect(coder.decode(%[{{{},{}},{{},{}}}])).to eql [[[],[]],[[],[]]]
      end

      it 'returns an array of strings with sub arrays' do
        expect(coder.decode(%[{1,{2,{3,4}},{NULL,,6},7}])).to eql ['1',['2',['3','4']],[nil,nil,'6'],'7']
      end
    end

    context 'record syntax' do
      it 'returns an empty array' do
        expect(coder.decode(%[()])).to eql []
      end

      it 'returns an array of strings' do
        expect(coder.decode(%[(1,2,3)])).to eql ['1','2','3']
      end

      it 'returns an array of strings, with nils replacing NULL characters' do
        expect(coder.decode(%[(1,,NULL)])).to eql ['1',nil,nil]
      end

      it 'returns an array with the word NULL' do
        expect(coder.decode(%[(1,"NULL",3)])).to eql ['1','NULL','3']
      end

      it 'returns an array of strings when containing commas in a quoted string' do
        expect(coder.decode(%[(1,"2,3",4)])).to eql ['1','2,3','4']
      end

      it 'returns an array of strings when containing an escaped quote' do
        expect(coder.decode(%[(1,"2\\",3",4)])).to eql ['1','2",3','4']
      end

      it 'returns an array of strings when containing an escaped backslash' do
        expect(coder.decode(%[(1,"2\\\\",3,4)])).to eql ['1','2\\','3','4']
        expect(coder.decode(%[(1,"2\\\\\\",3",4)])).to eql ['1','2\\",3','4']
      end

      it 'returns an array containing empty strings' do
        expect(coder.decode(%[(1,"",3,"")])).to eql ['1', '', '3', '']
      end

      it 'returns an array containing unicode strings' do
        expect(coder.decode(%[("Paragraph 399(b)(i) – “valid leave” – meaning")])).to eq(['Paragraph 399(b)(i) – “valid leave” – meaning'])
      end
    end

    context 'array of records' do
      it 'returns an empty array' do
        expect(coder.decode(%[{()}])).to eql [[]]
        expect(coder.decode(%[{(),()}])).to eql [[],[]]
      end

      it 'returns an array of strings with a sub array' do
        expect(coder.decode(%[{1,(2,3),4}])).to eql ['1',['2','3'],'4']
      end

      it 'returns an array of strings with a sub array' do
        expect(coder.decode(%[{1,("2,3"),4}])).to eql ['1',['2,3'],'4']
      end

      it 'returns an array of strings with a sub array and a quoted }' do
        expect(coder.decode(%[{1,("2,}3",,NULL),4}])).to eql ['1',['2,}3',nil,nil],'4']
      end

      it 'returns an array of strings with a sub array and a quoted {' do
        expect(coder.decode(%[{1,("2,{3"),4}])).to eql ['1',['2,{3'],'4']
      end

      it 'returns an array of strings with a sub array and a quoted { and escaped quote' do
        expect(coder.decode(%[{1,("2\\",{3"),4}])).to eql ['1',['2",{3'],'4']
      end

      it 'returns an array of strings with a sub array with empty strings' do
        expect(coder.decode(%[{1,(""),4,("")}])).to eql ['1',[''],'4',['']]
      end
    end

    context 'mix of record and array' do
      it 'returns an empty array' do
        expect(coder.decode(%[({()})])).to eql [[[]]]
        expect(coder.decode(%[{({},{}),{(),{}}}])).to eql [[[],[]],[[],[]]]
      end

      it 'returns an array of strings with sub arrays' do
        expect(coder.decode(%[{1,(2,{3,4}),(NULL,,6),7}])).to eql ['1',['2',['3','4']],[nil,nil,'6'],'7']
      end
    end

    context 'record complex sample' do
      it 'may have double double quotes translate to single double quotes' do
        expect(coder.decode(%[("Test with double "" quoutes")])).to eql ['Test with double " quoutes']
      end

      it 'double double quotes may occur any number of times' do
        expect(coder.decode(%[("Only one ""","Now "" two "".",""",""{""}","""""")])).to eql ['Only one "', 'Now " two ".', '","{"}', '""']
      end

      it 'may have any kind of value' do
        expect(coder.decode(%[(String,123456,false,true,"2016-01-01 12:00:00",{1,2,3})])).to eql ['String', '123456', 'false', 'true', '2016-01-01 12:00:00', ['1', '2', '3']]
      end
    end

  end

  context 'on encode' do
    let(:record) { Torque::PostgreSQL::Coder::Record }

    context 'one dimensional arrays' do
      it 'receives an empty array' do
        expect(coder.encode([])).to eql %[{}]
      end

      it 'receives an array of strings' do
        expect(coder.encode(['1','2','3'])).to eql %[{1,2,3}]
      end

      it 'receives an array of strings, with nils replacing NULL characters' do
        expect(coder.encode(['1',nil,nil])).to eql %[{1,NULL,NULL}]
      end

      it 'receives an array with the word NULL' do
        expect(coder.encode(['1','NULL','3'])).to eql %[{1,"NULL",3}]
      end

      it 'receives an array of strings when containing commas in a quoted string' do
        expect(coder.encode(['1','2,3','4'])).to eql %[{1,"2,3",4}]
      end

      it 'receives an array of strings when containing an escaped quote' do
        expect(coder.encode(['1','2",3','4'])).to eql %[{1,"2\\",3",4}]
      end

      it 'receives an array of strings when containing an escaped backslash' do
        expect(coder.encode(['1','2\\','3','4'])).to eql %[{1,"2\\\\",3,4}]
        expect(coder.encode(['1','2\\",3','4'])).to eql %[{1,"2\\\\\\",3",4}]
      end

      it 'receives an array containing empty strings' do
        expect(coder.encode(['1', '', '3', ''])).to eql %[{1,"",3,""}]
      end

      it 'receives an array containing unicode strings' do
        expect(coder.encode(['Paragraph 399(b)(i) – “valid leave” – meaning'])).to eql %[{"Paragraph 399(b)(i) – “valid leave” – meaning"}]
      end
    end

    context 'two dimensional arrays' do
      it 'receives an empty array' do
        expect(coder.encode([[]])).to eql %[{{}}]
        expect(coder.encode([[],[]])).to eql %[{{},{}}]
      end

      it 'receives an array of strings with a sub array' do
        expect(coder.encode(['1',['2','3'],'4'])).to eql %[{1,{2,3},4}]
      end

      it 'receives an array of strings with a sub array' do
        expect(coder.encode(['1',['2,3'],'4'])).to eql %[{1,{"2,3"},4}]
      end

      it 'receives an array of strings with a sub array and a quoted }' do
        expect(coder.encode(['1',['2,}3',nil,nil],'4'])).to eql %[{1,{"2,}3",NULL,NULL},4}]
      end

      it 'receives an array of strings with a sub array and a quoted {' do
        expect(coder.encode(['1',['2,{3'],'4'])).to eql %[{1,{"2,{3"},4}]
      end

      it 'receives an array of strings with a sub array and a quoted { and escaped quote' do
        expect(coder.encode(['1',['2",{3'],'4'])).to eql %[{1,{"2\\",{3"},4}]
      end

      it 'receives an array of strings with a sub array with empty strings' do
        expect(coder.encode(['1',[''],'4',['']])).to eql %[{1,{""},4,{""}}]
      end
    end

    context 'three dimensional arrays' do
      it 'receives an empty array' do
        expect(coder.encode([[[]]])).to eql %[{{{}}}]
        expect(coder.encode([[[],[]],[[],[]]])).to eql %[{{{},{}},{{},{}}}]
      end

      it 'receives an array of strings with sub arrays' do
        expect(coder.encode(['1',['2',['3','4']],[nil,nil,'6'],'7'])).to eql %[{1,{2,{3,4}},{NULL,NULL,6},7}]
      end
    end

    context 'record syntax' do
      it 'receives an empty array' do
        expect(coder.encode( record.new )).to eql %[()]
      end

      it 'receives an array of strings' do
        expect(coder.encode( record.new(['1','2','3']) )).to eql %[(1,2,3)]
      end

      it 'receives an array of strings, with nils replacing NULL characters' do
        expect(coder.encode( record.new(['1',nil,nil]) )).to eql %[(1,,)]
      end

      it 'receives an array with the word NULL' do
        expect(coder.encode( record.new(['1','NULL','3']) )).to eql %[(1,"NULL",3)]
      end

      it 'receives an array of strings when containing commas in a quoted string' do
        expect(coder.encode( record.new(['1','2,3','4']) )).to eql %[(1,"2,3",4)]
      end

      it 'receives an array of strings when containing an escaped quote' do
        expect(coder.encode( record.new(['1','2",3','4']) )).to eql %[(1,"2\\",3",4)]
      end

      it 'receives an array of strings when containing an escaped backslash' do
        expect(coder.encode( record.new(['1','2\\','3','4']) )).to eql %[(1,"2\\\\",3,4)]
        expect(coder.encode( record.new(['1','2\\",3','4']) )).to eql %[(1,"2\\\\\\",3",4)]
      end

      it 'receives an array containing empty strings' do
        expect(coder.encode( record.new(['1', '', '3', '']) )).to eql %[(1,"",3,"")]
      end

      it 'receives an array containing unicode strings' do
        expect(coder.encode( record.new(['Paragraph 399(b)(i) – “valid leave” – meaning']) )).to eql %[("Paragraph 399(b)(i) – “valid leave” – meaning")]
      end
    end

    context 'array of records' do
      it 'receives an empty array' do
        expect(coder.encode([record.new])).to eql %[{()}]
        expect(coder.encode([record.new,record.new])).to eql %[{(),()}]
      end

      it 'receives an array of strings with a sub array' do
        expect(coder.encode(['1',record.new(['2','3']),'4'])).to eql %[{1,(2,3),4}]
      end

      it 'receives an array of strings with a sub array' do
        expect(coder.encode(['1',record.new(['2,3']),'4'])).to eql %[{1,("2,3"),4}]
      end

      it 'receives an array of strings with a sub array and a quoted }' do
        expect(coder.encode(['1',record.new(['2,}3',nil,nil]),'4'])).to eql %[{1,("2,}3",,),4}]
      end

      it 'receives an array of strings with a sub array and a quoted {' do
        expect(coder.encode(['1',record.new(['2,{3']),'4'])).to eql %[{1,("2,{3"),4}]
      end

      it 'receives an array of strings with a sub array and a quoted { and escaped quote' do
        expect(coder.encode(['1',record.new(['2",{3']),'4'])).to eql %[{1,("2\\",{3"),4}]
      end

      it 'receives an array of strings with a sub array with empty strings' do
        expect(coder.encode(['1',record.new(['']),'4',record.new([''])])).to eql %[{1,(""),4,("")}]
      end
    end

    context 'mix of record and array' do
      it 'receives an empty array' do
        expect(coder.encode( record.new([[record.new,nil]]) )).to eql %[({(),NULL})]
        expect(coder.encode( [record.new([[], []]),[record.new,[]]] )).to eql %[{({},{}),{(),{}}}]
      end

      it 'receives an array of strings with sub arrays' do
        expect(coder.encode(['1',record.new(['2',['3','4']]),record.new([nil,nil,'6']),'7'])).to eql %[{1,(2,{3,4}),(,,6),7}]
      end
    end

    context 'record complex sample' do
      it 'may have double double quotes translate to single double quotes' do
        expect(coder.encode( record.new(['Test with double " quoutes']) )).to eql %[("Test with double \\" quoutes")]
      end

      it 'double double quotes may occur any number of times' do
        expect(coder.encode( record.new(['Only one "', 'Now " two ".', '","{"}', '""']) )).to eql %[("Only one \\"","Now \\" two \\".","\\",\\"{\\"}","\\"\\"")]
      end

      it 'may have any kind of value' do
        expect(coder.encode( record.new(['String', '123456', 'false', 'true', '2016-01-01 12:00:00', ['1', '2', '3']]) )).to eql %[(String,123456,false,true,"2016-01-01 12:00:00",{1,2,3})]
      end
    end

  end

end
