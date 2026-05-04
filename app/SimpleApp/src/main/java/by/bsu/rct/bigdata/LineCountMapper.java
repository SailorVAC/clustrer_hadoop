package by.bsu.rct.bigdata;

import org.apache.hadoop.io.LongWritable;
import org.apache.hadoop.io.NullWritable;
import org.apache.hadoop.io.Text;
import org.apache.hadoop.mapreduce.Mapper;

public class LineCountMapper extends Mapper<LongWritable, Text,
        NullWritable, LongWritable> {
    private final LongWritable one = new LongWritable (1);

    @Override
    protected void map(LongWritable key, Text value, Context context)
            throws java.io.IOException, InterruptedException {
        context.write(NullWritable.get(), one);
    }
}

