package by.bsu.rct.bigdata;

import org.apache.hadoop.io.LongWritable;
import org.apache.hadoop.io.NullWritable;
import org.apache.hadoop.io.Text;
import org.apache.hadoop.mapreduce.Reducer;

public class LineCountReducer extends Reducer<NullWritable, LongWritable,
        Text, LongWritable> {

    @Override
    protected void reduce(NullWritable key, Iterable<LongWritable> values,
                          Context context)
            throws java.io.IOException, InterruptedException {
        long count = 0;
        for (LongWritable val : values) { count += val.get(); }
        context.write(new Text("Number of lines:"), new LongWritable(count));
    }
}
